import AppKit

/// A web search shortcut such as `G query` or `GB images`.
struct SearchShortcut: Codable, Identifiable, Equatable {
    let id: UUID
    var prefix: String
    var name: String
    var searchTemplate: String
    var siteURL: String
    var tintHex: String
    var iconFileName: String?

    var siteURLValue: URL? { URL(string: siteURL) }

    var host: String {
        guard let host = siteURLValue?.host else { return siteURL }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var tint: NSColor {
        NSColor.cslHex(tintHex) ?? Theme.accent
    }

    /// Fully percent-encode the query and substitute it into the template.
    func url(for query: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        let template = searchTemplate.replacingOccurrences(
            of: "{query}",
            with: encoded,
            options: [.caseInsensitive]
        )
        return URL(string: template)
    }

    var searchURLIsValid: Bool {
        guard searchTemplate.range(of: "{query}", options: [.caseInsensitive]) != nil else { return false }
        return url(for: "test") != nil
    }
}

extension NSColor {
    static func cslHex(_ raw: String) -> NSColor? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}
