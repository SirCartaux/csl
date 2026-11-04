import AppKit

/// Reuses the website favicon pipeline for shortcut icons. The icon file is
/// stored by shortcut UUID, so no extra model field is needed.
final class ShortcutIconService {
    static let shared = ShortcutIconService()

    private init() {}

    func iconURL(for shortcut: SearchShortcut) -> URL? {
        iconURL(for: shortcut.id)
    }

    func iconURL(for id: UUID) -> URL? {
        let url = AppPaths.iconsDirectory.appendingPathComponent(id.uuidString + ".png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fetchIcon(for shortcut: SearchShortcut) {
        guard iconURL(for: shortcut) == nil else { return }
        FaviconService.shared.fetchIcon(for: website(for: shortcut))
    }

    func prefetchMissing() {
        let missing = ShortcutStore.shared.shortcuts.filter { iconURL(for: $0) == nil }
        for (index, shortcut) in missing.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.35) { [weak self] in
                self?.fetchIcon(for: shortcut)
            }
        }
    }

    func removeIcon(for id: UUID) {
        guard let url = iconURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
        IconCache.shared.invalidate(path: url.path)
    }

    private func website(for shortcut: SearchShortcut) -> WebsiteEntry {
        WebsiteEntry(
            id: shortcut.id,
            title: shortcut.name,
            url: shortcut.siteURL,
            iconFileName: nil
        )
    }
}
