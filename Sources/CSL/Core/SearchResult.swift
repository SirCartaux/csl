import AppKit

enum ResultKind {
    case application
    case file
    case command
    case website
}

enum ResultIcon {
    case file(URL)
    case image(URL)
    case glyph(PixelGlyph)
}

enum ResultAction {
    case open(URL)
    case reveal(URL)
    case run(() -> Void)
}

struct SearchResult {
    let id: String
    let title: String
    let subtitle: String
    let kind: ResultKind
    let icon: ResultIcon
    let score: Int
    let titleMatch: [NSRange]
    let action: ResultAction

    func withScore(_ newScore: Int) -> SearchResult {
        SearchResult(
            id: id,
            title: title,
            subtitle: subtitle,
            kind: kind,
            icon: icon,
            score: newScore,
            titleMatch: titleMatch,
            action: action
        )
    }
}

/// Central place for the app/file icons so scrolling and re-filtering does not
/// hit the filesystem or IconServices every keystroke.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for url: URL) -> NSImage {
        let key = url.path
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: key)
        cache[key] = image
        return image
    }

    func image(at url: URL) -> NSImage? {
        let key = "img:" + url.path
        if let cached = cache[key] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache[key] = image
        return image
    }

    func invalidate(path: String) {
        cache.removeValue(forKey: path)
        cache.removeValue(forKey: "img:" + path)
    }
}

enum PathDisplay {
    private static let cryptexPrefixes = [
        "/System/Cryptexes/App/System/Applications",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications"
    ]

    static func pretty(_ path: String) -> String {
        for prefix in cryptexPrefixes where path.hasPrefix(prefix) {
            return "/System/Applications" + path.dropFirst(prefix.count)
        }

        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func pretty(folderOf url: URL) -> String {
        pretty(url.deletingLastPathComponent().path)
    }
}
