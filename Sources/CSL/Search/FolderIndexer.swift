import Foundation
import QuartzCore

enum FolderIndexError: Error {
    case cancelled
    case unreadable
}

/// Walks a folder and builds index entries for it.
///
/// Phase 1 `scanning` counts and collects URLs (the total is unknown while it
/// runs, so the UI shows the live count). Phase 2 `indexing` turns every URL
/// into an entry, with an exact percentage and an ETA derived from throughput.
final class FolderIndexer {
    struct Progress {
        enum Phase: String {
            case scanning
            case indexing
            case saving
        }

        let phase: Phase
        let root: String
        let processed: Int
        let total: Int
        let fraction: Double
        let eta: TimeInterval?
        let currentItem: String?
        let truncated: Bool
    }

    private let stateLock = NSLock()
    private var cancelled = false
    private let maxEntries = 300_000
    private let testDelay: TimeInterval = ProcessInfo.processInfo.environment["CSL_INDEX_TEST_DELAY"]
        .flatMap(TimeInterval.init) ?? 0

    func cancel() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
    }

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    func index(
        root: String,
        progress: @escaping (Progress) -> Void,
        completion: @escaping (Result<[IndexedFile], FolderIndexError>) -> Void
    ) {
        stateLock.lock()
        cancelled = false
        stateLock.unlock()

        let settings = SettingsStore.shared.settings
        let rootURL = URL(fileURLWithPath: root)
        let rootName = rootURL.lastPathComponent

        DispatchQueue.global(qos: .userInitiated).async {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
                DispatchQueue.main.async { completion(.failure(.unreadable)) }
                return
            }

            // ---- Phase 1: scan -------------------------------------------------
            var items: [(url: URL, isDirectory: Bool)] = []
            var lastReport = CACurrentMediaTime()
            var truncated = false
            let scanStart = CACurrentMediaTime()

            if let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let url as URL in enumerator {
                    if self.isCancelled {
                        DispatchQueue.main.async { completion(.failure(.cancelled)) }
                        return
                    }

                    let path = url.path
                    if SearchExclusions.isExcluded(path)
                        || SettingsStore.path(path, isInsideAny: settings.ignoredFolders) {
                        if url.hasDirectoryPath {
                            enumerator.skipDescendants()
                        }
                        continue
                    }

                    let directory = url.hasDirectoryPath
                    if !directory, !settings.ignoredExtensions.isEmpty {
                        let ext = url.pathExtension.lowercased()
                        if settings.ignoredExtensions.contains(ext) { continue }
                    }

                    items.append((url, directory))
                    if items.count >= self.maxEntries {
                        truncated = true
                        break
                    }

                    let now = CACurrentMediaTime()
                    if now - lastReport >= 0.1 {
                        lastReport = now
                        let processed = items.count
                        let elapsed = now - scanStart
                        let rate = elapsed > 0 ? Double(processed) / elapsed : 0
                        DispatchQueue.main.async {
                            progress(Progress(
                                phase: .scanning,
                                root: root,
                                processed: processed,
                                total: 0,
                                fraction: 0,
                                eta: nil,
                                currentItem: url.lastPathComponent,
                                truncated: truncated
                            ))
                        }
                        Log.debug(String(
                            format: "scan %@: %d items (%.0f/s)",
                            rootName,
                            processed,
                            rate
                        ))
                    }
                }
            }

            let total = items.count
            let indexStart = CACurrentMediaTime()
            var entries: [IndexedFile] = []
            entries.reserveCapacity(total)
            lastReport = indexStart

            // ---- Phase 2: index ------------------------------------------------
            for (offset, item) in items.enumerated() {
                if self.isCancelled {
                    DispatchQueue.main.async { completion(.failure(.cancelled)) }
                    return
                }

                if self.testDelay > 0 {
                    Thread.sleep(forTimeInterval: self.testDelay)
                }

                let name = item.url.lastPathComponent
                let ext = item.isDirectory ? "" : item.url.pathExtension.lowercased()
                entries.append(IndexedFile(
                    path: item.url.path,
                    name: name,
                    lowerName: name.lowercased(),
                    isDirectory: item.isDirectory,
                    ext: ext,
                    root: root
                ))

                let processed = offset + 1
                let now = CACurrentMediaTime()
                if now - lastReport >= 0.1 || processed == total {
                    lastReport = now
                    let elapsed = now - indexStart
                    let rate = elapsed > 0.05 ? Double(processed) / elapsed : 0
                    let eta = rate > 0 && processed < total ? Double(total - processed) / rate : (processed == total ? 0 : nil)
                    let fraction = total > 0 ? Double(processed) / Double(total) : 0
                    let current = name
                    DispatchQueue.main.async {
                        progress(Progress(
                            phase: .indexing,
                            root: root,
                            processed: processed,
                            total: total,
                            fraction: fraction,
                            eta: eta,
                            currentItem: current,
                            truncated: truncated
                        ))
                    }
                }
            }

            if truncated {
                Log.debug("index \(rootName) truncated at \(self.maxEntries) entries")
            }
            Log.debug(String(
                format: "indexed %@: %d entries in %.2fs",
                rootName,
                entries.count,
                CACurrentMediaTime() - scanStart
            ))
            DispatchQueue.main.async { completion(.success(entries)) }
        }
    }
}
