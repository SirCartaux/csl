import AppKit
import QuartzCore

/// File search backed by the Spotlight index (`NSMetadataQuery`).
///
/// Two queries, two speeds:
///  • prefix query (`term*`)      – lands in ~15 ms, gives instant feedback
///  • substring query (`*term*`)  – lands in ~170 ms, only started after a
///    short idle pause, then merged in and re-ranked
///
/// Nothing is spawned, nothing walks the filesystem.
final class FileProvider {
    private var fastQuery: NSMetadataQuery?
    private var deepQuery: NSMetadataQuery?
    private var fastObservers: [NSObjectProtocol] = []
    private var deepObservers: [NSObjectProtocol] = []
    private var deepWork: DispatchWorkItem?
    private var onUpdate: (([SearchResult], Bool) -> Void)?
    private var term = ""
    private var candidates: [String: SearchResult] = [:]
    private var lastDelivered: [String] = []
    private var started: CFTimeInterval = 0
    private var finished = true
    private let limit = 16
    private let scanCap = 260
    private let deepDelay: TimeInterval = 0.11

    func search(_ term: String, onUpdate: @escaping ([SearchResult], Bool) -> Void) {
        cancel()

        self.term = term
        self.onUpdate = onUpdate
        self.candidates = [:]
        self.lastDelivered = []
        self.started = CACurrentMediaTime()
        self.finished = false

        let sanitized = term
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else {
            onUpdate([], true)
            return
        }

        // One character would match half the home folder and is never useful
        // for files; apps/commands still show up via the instant providers.
        guard sanitized.count >= 2 else {
            onUpdate([], true)
            return
        }

        startFastQuery(sanitized)

        let work = DispatchWorkItem { [weak self] in
            self?.startDeepQuery(sanitized)
        }
        deepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deepDelay, execute: work)
    }

    func cancel() {
        deepWork?.cancel()
        deepWork = nil
        fastObservers.forEach(NotificationCenter.default.removeObserver)
        deepObservers.forEach(NotificationCenter.default.removeObserver)
        fastObservers.removeAll()
        deepObservers.removeAll()
        fastQuery?.stop()
        deepQuery?.stop()
        fastQuery = nil
        deepQuery = nil
        onUpdate = nil
        finished = true
        candidates.removeAll()
    }

    // MARK: - Queries

    private func startFastQuery(_ term: String) {
        let query = makeQuery("kMDItemFSName LIKE[cd] '\(term)*'")
        fastQuery = query
        observe(query: query, prefix: true)
        query.start()
    }

    private func startDeepQuery(_ term: String) {
        guard !finished, deepQuery == nil, term.count >= 2 else { return }
        let query = makeQuery("kMDItemFSName LIKE[cd] '*\(term)*'")
        deepQuery = query
        observe(query: query, prefix: false)
        query.start()
        Log.debug(String(
            format: "deep file query started after %.1f ms",
            (CACurrentMediaTime() - started) * 1000
        ))
    }

    private func makeQuery(_ predicate: String) -> NSMetadataQuery {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: predicate)
        // No sortDescriptors: ranking happens in-process, and sorting the whole
        // Spotlight result set costs tens of milliseconds.
        query.notificationBatchingInterval = 0.015
        return query
    }

    private func observe(query: NSMetadataQuery, prefix: Bool) {
        let center = NotificationCenter.default
        let updateToken = center.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.harvest(query: query, prefix: prefix, final: false)
        }
        let finishToken = center.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.harvest(query: query, prefix: prefix, final: true)
        }
        if prefix {
            fastObservers.append(contentsOf: [updateToken, finishToken])
        } else {
            deepObservers.append(contentsOf: [updateToken, finishToken])
        }
    }

    // MARK: - Harvest

    private func harvest(query: NSMetadataQuery, prefix: Bool, final: Bool) {
        guard !finished, query === fastQuery || query === deepQuery else { return }

        query.disableUpdates()
        defer {
            if !finished { query.enableUpdates() }
        }

        let count = min(query.resultCount, scanCap)
        if count > 0 {
            for index in 0..<count {
                guard let item = query.result(at: index) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
                else { continue }

                let url = URL(fileURLWithPath: path)
                let name = url.lastPathComponent

                guard !name.hasPrefix("."),
                      url.pathExtension.lowercased() != "app",
                      !SearchExclusions.isExcluded(path),
                      !SettingsStore.shared.isIgnoredFast(path),
                      !SettingsStore.shared.isExtensionIgnored(url.pathExtension)
                else { continue }
                guard candidates[path] == nil else { continue }
                guard let match = FuzzyMatcher.match(term, in: name) else { continue }

                candidates[path] = SearchResult(
                    id: "file:" + path,
                    title: name,
                    subtitle: PathDisplay.pretty(folderOf: url),
                    kind: .file,
                    icon: .file(url),
                    score: min(match.score, 1000) + 20,
                    titleMatch: match.ranges,
                    action: .open(url)
                )
            }
        }

        if prefix {
            deliver(done: false)
        } else if final {
            finished = true
            query.stop()
            Log.debug(String(
                format: "file search done: %d results (%d candidates) after %.1f ms",
                topResults().count,
                candidates.count,
                (CACurrentMediaTime() - started) * 1000
            ))
            deliver(done: true)
        } else {
            deliver(done: false)
        }
    }

    private func deliver(done: Bool) {
        let top = topResults()
        let ids = top.map(\.id)
        let changed = ids != lastDelivered

        if changed {
            lastDelivered = ids
            Log.debug(String(
                format: "file results: %d after %.1f ms",
                top.count,
                (CACurrentMediaTime() - started) * 1000
            ))
        }

        if changed || done {
            onUpdate?(top, done)
        }
    }

    private func topResults() -> [SearchResult] {
        candidates.values
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title.count < $1.title.count
            }
            .prefix(limit)
            .map { $0 }
    }
}
