import Foundation
import QuartzCore

protocol SearchEngineDelegate: AnyObject {
    func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool)
}

/// Merges the synchronous providers (apps, commands) with the asynchronous
/// Spotlight file query. The synchronous part is emitted before this method
/// returns, so the UI paints something on the same tick as the keystroke.
final class SearchEngine {
    weak var delegate: SearchEngineDelegate?

    private let appProvider = AppProvider()
    private let commandProvider = CommandProvider()
    private let fileProvider = FileProvider()
    private let websiteProvider = WebsiteProvider()
    private let fileIndex = FileIndex.shared

    private var generation = 0
    private var currentQuery = ""
    private var instantResults: [SearchResult] = []
    private var fileResults: [SearchResult] = []
    private var fileSearching = false
    private var started: CFTimeInterval = 0
    private var loggedFirstUpdate = false

    var lastQuery: String { currentQuery }

    func warmUp() {
        appProvider.warmUp { [weak self] in
            guard let self else { return }
            // The user was faster than the index. Fold the apps in without
            // restarting the running file query.
            self.refreshInstantResults()
        }
    }

    func search(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        generation += 1
        let generation = self.generation
        fileProvider.cancel()

        currentQuery = trimmed
        fileResults = []
        fileSearching = !trimmed.isEmpty
        started = CACurrentMediaTime()
        loggedFirstUpdate = false

        guard !trimmed.isEmpty else {
            instantResults = commandProvider.allResults()
            fileSearching = false
            emit()
            return
        }

        instantResults = appProvider.results(for: trimmed)
            + commandProvider.results(for: trimmed)
            + websiteProvider.results(for: trimmed)
        instantResults.sort(by: Self.ranking)
        emit()
        searchIndex(for: trimmed, generation: generation)

        // The prefix query is cheap enough to start immediately; the provider
        // debounces only its slower substring pass internally.
        fileProvider.search(trimmed) { [weak self] results, done in
            guard let self, self.generation == generation else { return }
            self.fileResults = results
            self.fileSearching = !done
            self.emit()
        }
    }

    func cancel() {
        generation += 1
        fileProvider.cancel()
        fileSearching = false
    }

    private func refreshInstantResults() {
        started = CACurrentMediaTime()
        if currentQuery.isEmpty {
            instantResults = commandProvider.allResults()
        } else {
            instantResults = appProvider.results(for: currentQuery)
                + commandProvider.results(for: currentQuery)
                + websiteProvider.results(for: currentQuery)
            instantResults.sort(by: Self.ranking)
        }
        emit()
        if !currentQuery.isEmpty {
            searchIndex(for: currentQuery, generation: generation)
        }
    }

    private func searchIndex(for query: String, generation: Int) {
        fileIndex.searchAsync(for: query) { [weak self] results in
            guard let self, self.generation == generation, !results.isEmpty else { return }
            let known = Set(self.instantResults.map(\.id))
            let fresh = results.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }
            self.instantResults.append(contentsOf: fresh)
            self.instantResults.sort(by: Self.ranking)
            self.emit()
        }
    }

    /// Re-run the current query after settings or the index changed.
    func refresh() {
        if currentQuery.isEmpty {
            refreshInstantResults()
        } else {
            search(currentQuery)
        }
    }

    /// Only fold in new index entries; do not restart the Spotlight query.
    func refreshIndexResults() {
        guard !currentQuery.isEmpty else { return }
        searchIndex(for: currentQuery, generation: generation)
    }

    private func emit() {
        var seen = Set<String>()
        var merged = instantResults.filter { seen.insert($0.id).inserted }
        merged.append(contentsOf: fileResults.filter { seen.insert($0.id).inserted })
        merged = ResultRanker.shared.ranked(merged, query: currentQuery)
        if merged.count > 24 {
            merged.removeLast(merged.count - 24)
        }

        if !loggedFirstUpdate {
            loggedFirstUpdate = true
            Log.debug(String(
                format: "results: %d in %.1f ms (query: \"%@\")",
                merged.count,
                (CACurrentMediaTime() - started) * 1000,
                currentQuery
            ))
        }

        delegate?.searchEngine(self, didUpdate: merged, isSearching: fileSearching)
    }

    private static func ranking(_ lhs: SearchResult, _ rhs: SearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        let leftRank = kindRank(lhs.kind)
        let rightRank = kindRank(rhs.kind)
        if leftRank != rightRank { return leftRank < rightRank }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func kindRank(_ kind: ResultKind) -> Int {
        switch kind {
        case .application: return 0
        case .command: return 1
        case .website: return 2
        case .file: return 3
        }
    }
}
