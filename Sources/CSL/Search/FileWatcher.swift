import Foundation
import CoreServices

/// Keeps the custom file index in sync with the filesystem using FSEvents.
/// One coalesced kernel stream per indexed folder, no polling, and index
/// writes are debounced. Events are replayed from the last stored event ID
/// after a launch, so files created while CSL was closed are picked up too.
final class FileWatcher {
    static let shared = FileWatcher()

    private var streams: [String: Stream] = [:]
    private let eventQueue = DispatchQueue(label: "com.henri.csl.fsevents", qos: .utility)
    private let scanQueue = DispatchQueue(label: "com.henri.csl.fsevents.scan", qos: .utility)
    private var scanningPaths: Set<String> = []
    private var rescanRequested: Set<String> = []

    private init() {}

    static func currentEventID() -> UInt64 {
        FSEventsGetCurrentEventId()
    }

    // MARK: - Lifecycle (main thread)

    func sync() {
        assert(Thread.isMainThread)
        let folders = Set(SettingsStore.shared.settings.indexedFolders)

        let stale = streams.keys.filter { root in
            !folders.contains(root) || !FileManager.default.fileExists(atPath: root)
        }
        for root in stale {
            streams.removeValue(forKey: root)?.stop()
        }

        for root in folders where streams[root] == nil {
            guard FileManager.default.fileExists(atPath: root) else {
                Log.debug("watcher sync: missing root \(root)")
                continue
            }
            guard !IndexCoordinator.shared.isIndexing(folder: root) else { continue }
            guard FileIndex.shared.lastIndexed(forRoot: root) != nil else {
                Log.debug("watcher sync: no index yet for \(root)")
                continue
            }
            let since = FileIndex.shared.lastEventID(forRoot: root) ?? Self.currentEventID()
            start(root: root, since: since == 0 ? UInt64.max : since)
        }
    }

    func start(root: String, since: UInt64) {
        assert(Thread.isMainThread)
        streams.removeValue(forKey: root)?.stop()
        let stream = Stream(root: root, watcher: self, since: since, queue: eventQueue)
        streams[root] = stream
        stream.start()
    }

    func stop(root: String) {
        assert(Thread.isMainThread)
        streams.removeValue(forKey: root)?.stop()
    }

    func stopAll() {
        assert(Thread.isMainThread)
        for (_, stream) in streams {
            stream.stop()
        }
        streams.removeAll()
    }

    // MARK: - Event handling

    fileprivate func handle(
        stream: Stream,
        count: Int,
        paths: UnsafeMutableRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>,
        ids: UnsafePointer<FSEventStreamEventId>
    ) {
        guard count > 0 else { return }
        let pathArray = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
        guard pathArray.count >= count else { return }

        let root = stream.root
        let fileManager = FileManager.default
        var additions: [IndexedFile] = []
        var additionsSeen = Set<String>()
        var removals = Set<String>()
        var dirsToScan = Set<String>()
        var mustRescan = false
        var rootGone = false
        var lastEventID: UInt64 = 0

        for index in 0..<count {
            lastEventID = max(lastEventID, ids[index])
            let path = pathArray[index]
            let eventFlags = flags[index]

            if eventFlags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 {
                continue
            }
            if eventFlags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0
                || eventFlags & UInt32(kFSEventStreamEventFlagUserDropped) != 0
                || eventFlags & UInt32(kFSEventStreamEventFlagKernelDropped) != 0
                || eventFlags & UInt32(kFSEventStreamEventFlagEventIdsWrapped) != 0
                || eventFlags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
                mustRescan = true
            }

            if path == root {
                var isDirectory: ObjCBool = false
                if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
                    rootGone = true
                }
                continue
            }

            let name = (path as NSString).lastPathComponent
            if name.hasPrefix(".") || path.contains(".sb-") { continue }
            if path.contains(".app/") || path.contains(".photoslibrary/")
                || path.contains(".bundle/") || path.contains(".framework/") { continue }
            if SearchExclusions.isExcluded(path) { continue }

            if (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                continue
            }

            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
                let directory = isDirectory.boolValue
                let ext = directory ? "" : (path as NSString).pathExtension.lowercased()
                if additionsSeen.insert(path).inserted {
                    additions.append(IndexedFile(
                        path: path,
                        name: name,
                        lowerName: name.lowercased(),
                        isDirectory: directory,
                        ext: ext,
                        root: root
                    ))
                }
                if directory, eventFlags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                    dirsToScan.insert(path)
                }
            } else {
                removals.insert(path)
            }
        }

        if rootGone {
            // An unmounted external drive should not throw away its index.
            // Keep the entries; a remount/reindex can resync them.
            DispatchQueue.main.async { [weak self] in
                Log.debug("watcher root unavailable, keeping index: \(root)")
                self?.stop(root: root)
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let settings = SettingsStore.shared

            var accepted: [IndexedFile] = []
            accepted.reserveCapacity(additions.count)
            for entry in additions {
                if settings.isIgnoredFast(entry.path) { continue }
                if !entry.ext.isEmpty, settings.isExtensionIgnored(entry.ext) { continue }
                accepted.append(entry)
            }

            FileIndex.shared.apply(additions: accepted, removals: Array(removals))
            if lastEventID > 0 {
                FileIndex.shared.setLastEventID(lastEventID, forRoot: root)
            }
            if mustRescan {
                self.requestRescan(root: root)
            }
        }

        for directory in dirsToScan {
            scheduleScan(directory: directory, root: root)
        }
    }

    // MARK: - Scans

    private func scheduleScan(directory: String, root: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.scanningPaths.contains(directory) else { return }
            self.scanningPaths.insert(directory)
            let settings = SettingsStore.shared.settings

            self.scanQueue.async {
                let entries = Self.scan(directory: directory, root: root, settings: settings)
                DispatchQueue.main.async {
                    self.scanningPaths.remove(directory)
                    if !entries.isEmpty {
                        FileIndex.shared.apply(additions: entries, removals: [])
                    }
                }
            }
        }
    }

    private static func scan(directory: String, root: String, settings: CSLSettings) -> [IndexedFile] {
        let url = URL(fileURLWithPath: directory)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let limit = 100_000
        var entries: [IndexedFile] = []
        for case let child as URL in enumerator {
            if entries.count >= limit {
                Log.debug("watcher subtree scan truncated at \(limit): \(directory)")
                break
            }
            let path = child.path
            if SearchExclusions.isExcluded(path)
                || SettingsStore.path(path, isInsideAny: settings.ignoredFolders) {
                if child.hasDirectoryPath {
                    enumerator.skipDescendants()
                }
                continue
            }
            if path.contains(".app/") || path.contains(".sb-") { continue }

            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }
            let isDirectory = child.hasDirectoryPath
            let ext = isDirectory ? "" : child.pathExtension.lowercased()
            if !ext.isEmpty, settings.ignoredExtensions.contains(ext) { continue }

            entries.append(IndexedFile(
                path: path,
                name: name,
                lowerName: name.lowercased(),
                isDirectory: isDirectory,
                ext: ext,
                root: root
            ))
        }
        return entries
    }

    private func requestRescan(root: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.rescanRequested.contains(root) else { return }
            self.rescanRequested.insert(root)
            IndexCoordinator.shared.index(folder: root)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.rescanRequested.remove(root)
            }
        }
    }
}

// MARK: - Stream

private final class Stream {
    let root: String
    weak var watcher: FileWatcher?
    let since: UInt64
    let queue: DispatchQueue
    private var stream: FSEventStreamRef?

    init(root: String, watcher: FileWatcher, since: UInt64, queue: DispatchQueue) {
        self.root = root
        self.watcher = watcher
        self.since = since
        self.queue = queue
    }

    func start() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            guard let info else { return }
            let stream = Unmanaged<Stream>.fromOpaque(info).takeUnretainedValue()
            stream.watcher?.handle(
                stream: stream,
                count: count,
                paths: paths,
                flags: flags,
                ids: ids
            )
        }

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagWatchRoot)

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [root] as CFArray,
            since,
            0.8,
            flags
        ) else {
            Log.debug("FSEvents create failed for \(root)")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            Log.debug("FSEvents start failed for \(root)")
        } else {
            Log.debug("FSEvents watching \(root) since \(since)")
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
