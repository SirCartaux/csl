import Foundation

struct IndexedFile: Codable, Equatable {
    let path: String
    let name: String
    let lowerName: String
    let isDirectory: Bool
    let ext: String
    let root: String
}

struct IndexRootMeta: Codable {
    var count: Int
    var lastIndexed: Date
    var lastEventID: UInt64?
}

struct StoredIndex: Codable {
    var entries: [IndexedFile] = []
    var roots: [String: IndexRootMeta] = [:]
}

/// In-memory index for folders the user explicitly added. Filled by
/// FolderIndexer (with progress), kept fresh by FileWatcher (FSEvents) and
/// persisted to index.json. Searched off the main thread.
final class FileIndex {
    static let shared = FileIndex()

    private(set) var roots: [String: IndexRootMeta] = [:]
    private(set) var isLoaded = false

    private var entriesByPath: [String: IndexedFile] = [:]
    private var pathsByRoot: [String: Set<String>] = [:]
    private var cachedEntries: [IndexedFile] = []
    private var cacheDirty = true

    private let ioQueue = DispatchQueue(label: "com.henri.csl.index-io", qos: .utility)
    private let searchQueue = DispatchQueue(label: "com.henri.csl.index-search", qos: .userInteractive)
    private let tokenLock = NSLock()
    private var searchToken = 0

    private var didStartLoading = false
    private var loadCompletions: [() -> Void] = []
    private var saveWorkItem: DispatchWorkItem?
    private var changeWorkItem: DispatchWorkItem?
    private var isDirty = false

    private init() {}

    var totalCount: Int { entriesByPath.count }

    // MARK: - Loading / saving

    func loadAsync(completion: (() -> Void)? = nil) {
        if isLoaded {
            completion?()
            return
        }
        if let completion { loadCompletions.append(completion) }
        guard !didStartLoading else { return }
        didStartLoading = true

        ioQueue.async {
            let stored = Self.readFromDisk()
            DispatchQueue.main.async {
                self.entriesByPath.removeAll(keepingCapacity: true)
                self.pathsByRoot.removeAll(keepingCapacity: true)
                for entry in stored.entries {
                    self.entriesByPath[entry.path] = entry
                    self.pathsByRoot[entry.root, default: []].insert(entry.path)
                }
                self.roots = stored.roots
                for (root, paths) in self.pathsByRoot {
                    if self.roots[root] == nil {
                        self.roots[root] = IndexRootMeta(count: paths.count, lastIndexed: Date())
                    } else {
                        self.roots[root]?.count = paths.count
                    }
                }
                self.cacheDirty = true
                self.isLoaded = true
                Log.debug("index loaded: \(self.entriesByPath.count) entries, \(self.roots.count) roots")
                NotificationCenter.default.post(name: .cslIndexLoaded, object: nil)
                let completions = self.loadCompletions
                self.loadCompletions.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    private static func readFromDisk() -> StoredIndex {
        guard let data = try? Data(contentsOf: AppPaths.indexFile) else {
            return StoredIndex()
        }
        do {
            return try JSONDecoder().decode(StoredIndex.self, from: data)
        } catch {
            Log.debug("index decode failed: \(error)")
            return StoredIndex()
        }
    }

    /// Replaces the entries of one root, then persists off the main thread.
    func commit(
        root: String,
        entries newEntries: [IndexedFile],
        lastEventID: UInt64? = nil,
        completion: @escaping () -> Void
    ) {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        if let oldPaths = pathsByRoot[root] {
            for path in oldPaths {
                entriesByPath.removeValue(forKey: path)
            }
        }

        var newPaths = Set<String>()
        newPaths.reserveCapacity(newEntries.count)
        for entry in newEntries {
            entriesByPath[entry.path] = entry
            newPaths.insert(entry.path)
        }
        pathsByRoot[root] = newPaths

        var meta = IndexRootMeta(count: newPaths.count, lastIndexed: Date())
        meta.lastEventID = lastEventID ?? roots[root]?.lastEventID
        roots[root] = meta
        cacheDirty = true
        isDirty = false

        let snapshot = makeStoredIndex()
        ioQueue.async {
            Self.writeToDisk(snapshot)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cslIndexFinished, object: root)
                completion()
            }
        }
    }

    func removeRoot(_ root: String) {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        if let oldPaths = pathsByRoot.removeValue(forKey: root) {
            for path in oldPaths {
                entriesByPath.removeValue(forKey: path)
            }
        }
        roots.removeValue(forKey: root)
        cacheDirty = true
        isDirty = false

        let snapshot = makeStoredIndex()
        ioQueue.async {
            Self.writeToDisk(snapshot)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .cslIndexChanged, object: nil)
        }
    }

    func clearAll() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        entriesByPath.removeAll()
        pathsByRoot.removeAll()
        roots.removeAll()
        cacheDirty = true
        isDirty = false
        let snapshot = StoredIndex()
        ioQueue.async {
            Self.writeToDisk(snapshot)
        }
    }

    /// Watchdog updates: upsert changed files and remove deleted paths.
    func apply(additions: [IndexedFile], removals: [String]) {
        guard isLoaded, !(additions.isEmpty && removals.isEmpty) else { return }

        var changed = false
        for entry in additions {
            if let existing = entriesByPath[entry.path] {
                if existing == entry { continue }
                if existing.root != entry.root {
                    pathsByRoot[existing.root]?.remove(entry.path)
                }
            }
            entriesByPath[entry.path] = entry
            pathsByRoot[entry.root, default: []].insert(entry.path)
            if roots[entry.root] == nil {
                roots[entry.root] = IndexRootMeta(count: 0, lastIndexed: Date())
            }
            changed = true
        }

        if !removals.isEmpty {
            var doomed: [String] = []
            for path in entriesByPath.keys where removals.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                doomed.append(path)
            }
            for path in doomed {
                if let entry = entriesByPath.removeValue(forKey: path) {
                    pathsByRoot[entry.root]?.remove(path)
                    changed = true
                }
            }
        }

        guard changed else { return }
        for root in roots.keys {
            roots[root]?.count = pathsByRoot[root]?.count ?? 0
        }
        cacheDirty = true
        isDirty = true
        scheduleSave()
        scheduleChangeNotification()
    }

    func lastEventID(forRoot root: String) -> UInt64? {
        roots[root]?.lastEventID
    }

    func setLastEventID(_ id: UInt64, forRoot root: String) {
        guard id > 0, var meta = roots[root], meta.lastEventID != id else { return }
        meta.lastEventID = id
        roots[root] = meta
        isDirty = true
        scheduleSave()
    }

    private func makeStoredIndex() -> StoredIndex {
        StoredIndex(entries: Array(entriesByPath.values), roots: roots)
    }

    private static func writeToDisk(_ stored: StoredIndex) {
        AppPaths.prepare()
        do {
            let data = try JSONEncoder().encode(stored)
            try data.write(to: AppPaths.indexFile, options: .atomic)
            Log.debug("index saved: \(stored.entries.count) entries (\(data.count / 1024) KB)")
        } catch {
            Log.debug("index save failed: \(error)")
        }
    }

    private func scheduleSave(delay: TimeInterval = 2.5) {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveWorkItem = nil
            self?.saveNow()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func saveNow() {
        guard isLoaded, isDirty else { return }
        isDirty = false
        let snapshot = makeStoredIndex()
        ioQueue.async {
            Self.writeToDisk(snapshot)
        }
    }

    /// Called on app termination. Blocks until the latest index is on disk.
    func flush() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard isLoaded, isDirty else { return }
        isDirty = false
        let snapshot = makeStoredIndex()
        ioQueue.sync {
            Self.writeToDisk(snapshot)
        }
    }

    private func scheduleChangeNotification() {
        changeWorkItem?.cancel()
        let work = DispatchWorkItem {
            NotificationCenter.default.post(name: .cslIndexChanged, object: nil)
        }
        changeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: - Queries

    func count(forRoot root: String) -> Int {
        pathsByRoot[root]?.count ?? roots[root]?.count ?? 0
    }

    func lastIndexed(forRoot root: String) -> Date? {
        roots[root]?.lastIndexed
    }

    private func searchSnapshot() -> [IndexedFile] {
        if cacheDirty {
            cachedEntries = Array(entriesByPath.values)
            cacheDirty = false
        }
        return cachedEntries
    }

    func results(for query: String, limit: Int = 16) -> [SearchResult] {
        guard isLoaded, !entriesByPath.isEmpty, query.count >= 2 else { return [] }
        let settings = SettingsStore.shared.settings
        let snapshot = searchSnapshot()
        return Self.search(
            snapshot,
            needle: query.lowercased(),
            ignoredFolders: settings.ignoredFolders,
            ignoredExtensions: Set(settings.ignoredExtensions),
            limit: limit,
            isCancelled: { false },
            progress: nil
        )
    }

    /// Runs the substring scan off the main thread. The array snapshot is
    /// captured on the main thread, so later commits cannot mutate it.
    func searchAsync(
        for query: String,
        progress: ((Int, Int) -> Void)? = nil,
        batch: (([SearchResult]) -> Void)? = nil,
        completion: @escaping ([SearchResult]) -> Void
    ) {
        guard isLoaded, !entriesByPath.isEmpty, query.count >= 2 else {
            completion([])
            return
        }
        let snapshot = searchSnapshot()
        let settings = SettingsStore.shared.settings
        let needle = query.lowercased()
        let ignoredFolders = settings.ignoredFolders
        let ignoredExtensions = Set(settings.ignoredExtensions)

        tokenLock.lock()
        searchToken += 1
        let token = searchToken
        tokenLock.unlock()

        searchQueue.async {
            let matches = Self.search(
                snapshot,
                needle: needle,
                ignoredFolders: ignoredFolders,
                ignoredExtensions: ignoredExtensions,
                limit: Int.max,
                isCancelled: { [weak self] in
                    guard let self else { return true }
                    self.tokenLock.lock()
                    let current = self.searchToken
                    self.tokenLock.unlock()
                    return current != token
                },
                progress: { scanned, total in
                    guard let progress else { return }
                    DispatchQueue.main.async {
                        progress(scanned, total)
                    }
                },
                batch: { results in
                    guard let batch else { return }
                    DispatchQueue.main.async {
                        batch(results)
                    }
                }
            )
            DispatchQueue.main.async { completion(matches) }
        }
    }

    private static func search(
        _ entries: [IndexedFile],
        needle: String,
        ignoredFolders: [String],
        ignoredExtensions: Set<String>,
        limit: Int,
        isCancelled: () -> Bool,
        progress: ((Int, Int) -> Void)? = nil,
        batch: (([SearchResult]) -> Void)? = nil
    ) -> [SearchResult] {
        var matches: [SearchResult] = []
        var pendingBatch: [SearchResult] = []
        let total = entries.count
        let likelyThreshold = 750
        progress?(0, total)

        for (index, entry) in entries.enumerated() {
            if index % 2048 == 0 {
                progress?(index, total)
                if !pendingBatch.isEmpty {
                    batch?(pendingBatch)
                    pendingBatch.removeAll(keepingCapacity: true)
                }
            }
            if index % 512 == 0, isCancelled() { return [] }
            if !entry.ext.isEmpty, ignoredExtensions.contains(entry.ext) { continue }
            if !ignoredFolders.isEmpty, SettingsStore.path(entry.path, isInsideAny: ignoredFolders) { continue }
            if SearchExclusions.isExcluded(entry.path) { continue }

            let lower = entry.lowerName as NSString
            let found = lower.range(of: needle)
            guard found.location != NSNotFound else { continue }

            var score = 720
            if found.location == 0 {
                score = 900
            } else {
                let previous = lower.character(at: found.location - 1)
                let isWordCharacter = (previous >= 48 && previous <= 57)
                    || (previous >= 65 && previous <= 90)
                    || (previous >= 97 && previous <= 122)
                if !isWordCharacter { score = 830 }
                score -= min(120, found.location * 2)
            }
            score -= min(70, (lower.length - found.length) * 2)
            let likelyScore = min(score, 1000) + 20
            // Mid-word substring hits are too noisy; include every prefix /
            // word-boundary match, which is what counts as likely.
            guard likelyScore >= likelyThreshold else { continue }

            let url = URL(fileURLWithPath: entry.path)
            let result = SearchResult(
                id: "file:" + entry.path,
                title: entry.name,
                subtitle: PathDisplay.pretty(folderOf: url),
                kind: .file,
                icon: .file(url),
                score: likelyScore,
                titleMatch: [found],
                action: .open(url)
            )
            matches.append(result)
            pendingBatch.append(result)
            if pendingBatch.count >= 128 {
                batch?(pendingBatch)
                pendingBatch.removeAll(keepingCapacity: true)
            }
        }

        if !pendingBatch.isEmpty {
            batch?(pendingBatch)
        }
        progress?(total, total)
        guard !matches.isEmpty else { return [] }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.title.count < $1.title.count
        }

        var seenPaths = Set<String>()
        return Array(matches
            .filter { seenPaths.insert($0.id).inserted }
            .prefix(limit))
    }

}
