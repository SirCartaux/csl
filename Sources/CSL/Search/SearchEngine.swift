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
    var onIndexProgress: ((Int, Int, Bool) -> Void)?

    private let appProvider = AppProvider()
    private let commandProvider = CommandProvider()
    private let fileProvider = FileProvider()
    private let websiteProvider = WebsiteProvider()
    private let fileIndex = FileIndex.shared
    private let fileCache = FileResultCache.shared

    private var generation = 0
    private var searchActive = false
    private var streamUpdate: DispatchWorkItem?
    private var streamedIDs = Set<String>()
    private var deliveredFirstBatch = false
    private var currentQuery = ""
    private var instantResults: [SearchResult] = []
    private var cachedFileResults: [SearchResult] = []
    private var streamedFileResults: [SearchResult] = []
    private var fileResults: [SearchResult] = []
    private var fileSearching = false
    private var indexSearching = false
    private var started: CFTimeInterval = 0
    private var loggedFirstUpdate = false

    var lastQuery: String { currentQuery }

    func warmUp() {
        appProvider.warmUp { [weak self] in
            guard let self, self.searchActive else { return }
            // The user was faster than the index. Fold the apps in without
            // restarting the running file query.
            self.refreshInstantResults()
        }
    }

    func search(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        searchActive = true
        streamUpdate?.cancel(); streamUpdate = nil
        fileIndex.cancelSearch()
        generation += 1
        let generation = self.generation
        fileProvider.cancel()
        onIndexProgress?(0, 0, true)

        currentQuery = trimmed
        fileResults = []
        cachedFileResults = []
        streamedFileResults = []
        fileSearching = !trimmed.isEmpty
        indexSearching = !trimmed.isEmpty
        started = CACurrentMediaTime()
        loggedFirstUpdate = false

        guard !trimmed.isEmpty else {
            instantResults = commandProvider.allResults()
            fileSearching = false
            indexSearching = false
            emit()
            return
        }

        if let google = WebSearchProvider.result(for: trimmed) {
            instantResults = [google]
            fileSearching = false
            indexSearching = false
            emit()
            return
        }

        instantResults = appProvider.results(for: trimmed)
            + commandProvider.results(for: trimmed)
            + websiteProvider.results(for: trimmed)
        let cached = fileCache.results(for: trimmed)
        cachedFileResults = cached
        instantResults.append(contentsOf: cached)
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
        searchActive = false
        streamUpdate?.cancel(); streamUpdate = nil
        fileIndex.cancelSearch()
        generation += 1
        fileProvider.cancel()
        cachedFileResults = []
        streamedFileResults = []
        fileSearching = false
        indexSearching = false
        onIndexProgress?(0, 0, true)
    }

    private func refreshInstantResults() {
        started = CACurrentMediaTime()
        if currentQuery.isEmpty {
            instantResults = commandProvider.allResults()
        } else if let google = WebSearchProvider.result(for: currentQuery) {
            instantResults = [google]
            fileSearching = false
        } else {
            instantResults = appProvider.results(for: currentQuery)
                + commandProvider.results(for: currentQuery)
                + websiteProvider.results(for: currentQuery)
            let known = Set(instantResults.map(\.id))
            let cached = fileCache.results(for: currentQuery)
                .filter { !known.contains($0.id) }
            cachedFileResults = cached
            instantResults.append(contentsOf: cached)
            instantResults.sort(by: Self.ranking)
        }
        emit()
        if !currentQuery.isEmpty, WebSearchProvider.query(from: currentQuery) == nil {
            searchIndex(for: currentQuery, generation: generation)
        }
    }

    private func searchIndex(for query: String, generation: Int) {
        indexSearching = true
        streamUpdate?.cancel(); streamUpdate = nil
        streamedFileResults = []
        streamedIDs.removeAll(keepingCapacity: true)
        deliveredFirstBatch = false
        let total = fileIndex.totalCount
        if total > 0 {
            onIndexProgress?(0, total, false)
        }

        fileIndex.searchAsync(for: query, progress: { [weak self] scanned, total in
            guard let self, self.generation == generation else { return }
            self.onIndexProgress?(scanned, total, false)
        }, batch: { [weak self] batch in
            guard let self, self.generation == generation else { return }
            let fresh = batch.filter { self.streamedIDs.insert($0.id).inserted }
            guard !fresh.isEmpty else { return }
            self.streamedFileResults.append(contentsOf: fresh)
            // Re-rank the complete pool so each newly found hit appears at its
            // rule-based position, not at the bottom of the list.
            self.emitStreamUpdate()
            Log.debug("file stream: +\(fresh.count) (\(self.streamedFileResults.count) total, query: \"\(query)\")")
        }) { [weak self] results in
            guard let self, self.generation == generation else { return }
            self.streamUpdate?.cancel(); self.streamUpdate = nil
            self.indexSearching = false
            self.onIndexProgress?(total, total, true)

            // Replace the cached first screenful with the complete, sorted
            // index result.
            if !self.cachedFileResults.isEmpty {
                let cachedIDs = Set(self.cachedFileResults.map(\.id))
                self.instantResults.removeAll { cachedIDs.contains($0.id) }
                self.cachedFileResults = []
            }

            Log.debug(String(
                format: "index complete: %d after %.1f ms (query: \"%@\")",
                results.count,
                (CACurrentMediaTime() - self.started) * 1000,
                query
            ))
            self.streamedFileResults = results
            // Only the finished search is allowed to populate the cache, and
            // it stores the first 7 files in their final ranked order.
            let rankedFiles = ResultRanker.shared.ranked(results, query: query)
            FileResultCache.shared.store(rankedFiles, for: query)
            self.emit()
        }
    }

    /// Re-run the current query after settings or the index changed.
    func refresh() {
        guard searchActive else { return }
        if currentQuery.isEmpty {
            refreshInstantResults()
        } else {
            search(currentQuery)
        }
    }

    /// Only fold in new index entries; do not restart the Spotlight query.
    func refreshIndexResults() {
        guard searchActive, !currentQuery.isEmpty, WebSearchProvider.query(from: currentQuery) == nil else { return }
        searchIndex(for: currentQuery, generation: generation)
    }

    /// Keep the very first hit immediate; merge later bursts once per frame.
    private func emitStreamUpdate() {
        if !deliveredFirstBatch {
            deliveredFirstBatch = true
            emit()
            return
        }
        guard streamUpdate == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.streamUpdate = nil
            self.emit()
        }
        streamUpdate = work
        DispatchQueue.main.asyncAfter(deadline: .now()+1.0/60.0, execute: work)
    }

    private func emit() {
        var seen = Set<String>()
        var merged = instantResults.filter { seen.insert($0.id).inserted }
        merged.append(contentsOf: streamedFileResults.filter { seen.insert($0.id).inserted })
        merged.append(contentsOf: fileResults.filter { seen.insert($0.id).inserted })
        merged = ResultRanker.shared.ranked(merged, query: currentQuery)

        if !loggedFirstUpdate {
            loggedFirstUpdate = true
            Log.debug(String(
                format: "results: %d in %.1f ms (query: \"%@\")",
                merged.count,
                (CACurrentMediaTime() - started) * 1000,
                currentQuery
            ))
        }

        delegate?.searchEngine(self, didUpdate: merged, isSearching: fileSearching || indexSearching)
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
