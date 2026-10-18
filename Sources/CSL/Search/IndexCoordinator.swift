import Foundation

/// Queues index jobs and broadcasts their progress to the settings UI.
final class IndexCoordinator {
    static let shared = IndexCoordinator()

    private let indexer = FolderIndexer()
    private var pending: [String] = []
    private var activeRoot: String?
    private(set) var isIndexing = false
    private(set) var latestProgress: FolderIndexer.Progress?

    private init() {}

    // MARK: - Public API

    func index(folder: String) {
        let normalized = SettingsStore.normalizeFolder(folder)
        guard SettingsStore.shared.settings.indexedFolders.contains(normalized) else { return }
        guard !pending.contains(normalized), activeRoot != normalized else { return }
        pending.append(normalized)
        startNextIfNeeded()
    }

    func indexAll() {
        for folder in SettingsStore.shared.settings.indexedFolders {
            if !pending.contains(folder), activeRoot != folder {
                pending.append(folder)
            }
        }
        startNextIfNeeded()
    }

    func indexMissing() {
        guard FileIndex.shared.isLoaded else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.indexMissing()
            }
            return
        }

        for folder in SettingsStore.shared.settings.indexedFolders
        where FileIndex.shared.lastIndexed(forRoot: folder) == nil {
            if !pending.contains(folder), activeRoot != folder {
                pending.append(folder)
            }
        }
        startNextIfNeeded()
    }

    func cancelAll() {
        pending.removeAll()
        if isIndexing {
            indexer.cancel()
        }
    }

    func cancel(folder: String) {
        let normalized = SettingsStore.normalizeFolder(folder)
        pending.removeAll { $0 == normalized }
        if activeRoot == normalized {
            indexer.cancel()
        }
    }

    func isIndexing(folder: String) -> Bool {
        activeRoot == SettingsStore.normalizeFolder(folder)
    }

    func removeFolder(_ folder: String) {
        let normalized = SettingsStore.normalizeFolder(folder)
        cancel(folder: normalized)
        FileWatcher.shared.stop(root: normalized)
        FileIndex.shared.removeRoot(normalized)
    }

    // MARK: - Job handling

    private func startNextIfNeeded() {
        guard !isIndexing else { return }

        while !pending.isEmpty {
            let root = pending.removeFirst()
            guard SettingsStore.shared.settings.indexedFolders.contains(root) else { continue }
            guard FileManager.default.fileExists(atPath: root) else {
                Log.debug("skip missing index root: \(root)")
                continue
            }

            // Stop watching while the full scan runs. We remember the global
            // event ID and replay everything that happened during indexing
            // afterwards, so no change is lost.
            FileWatcher.shared.stop(root: root)
            let startEventID = FileWatcher.currentEventID()

            isIndexing = true
            activeRoot = root
            latestProgress = nil
            postState()

            indexer.index(root: root) { [weak self] progress in
                guard let self else { return }
                self.latestProgress = progress
                NotificationCenter.default.post(
                    name: .cslIndexProgress,
                    object: nil,
                    userInfo: ["progress": progress]
                )
            } completion: { [weak self] result in
                guard let self else { return }

                switch result {
                case .success(let entries):
                    let final = FolderIndexer.Progress(
                        phase: .saving,
                        root: root,
                        processed: entries.count,
                        total: entries.count,
                        fraction: 1,
                        eta: 0,
                        currentItem: nil,
                        truncated: false
                    )
                    self.latestProgress = final
                    NotificationCenter.default.post(
                        name: .cslIndexProgress,
                        object: nil,
                        userInfo: ["progress": final]
                    )

                    FileIndex.shared.commit(
                        root: root,
                        entries: entries,
                        lastEventID: startEventID > 0 ? startEventID : nil
                    ) { [weak self] in
                        guard let self else { return }
                        self.finishJob()
                    }

                case .failure(let error):
                    Log.debug("index job failed for \(root): \(error)")
                    self.finishJob()
                }
            }
            return
        }
    }

    private func finishJob() {
        isIndexing = false
        activeRoot = nil
        latestProgress = nil
        postState()
        FileWatcher.shared.sync()
        startNextIfNeeded()
    }

    private func postState() {
        NotificationCenter.default.post(
            name: .cslIndexStateChanged,
            object: nil,
            userInfo: ["isIndexing": isIndexing]
        )
    }
}
