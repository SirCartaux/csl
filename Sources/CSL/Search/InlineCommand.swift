import AppKit

enum ProcessCommand: String, CaseIterable {
    case stop, restart

    var tint: NSColor { self == .stop ? NSColor(srgbRed: 1, green: 0.38, blue: 0.35, alpha: 1) : Theme.accent }
    var label: String { rawValue.uppercased() }
}

/// One parser supplies both routing and input styling. The range refers to the
/// original UTF-16 string, so leading spaces and non-ASCII queries remain editable.
struct InlineCommand {
    enum Kind {
        case process(ProcessCommand)
        case shortcut(SearchShortcut)
        case google
    }

    let kind: Kind
    let prefixRange: NSRange
    let query: String

    var tint: NSColor {
        switch kind {
        case .process(let command): return command.tint
        case .shortcut(let shortcut): return shortcut.tint
        case .google: return NSColor.cslHex("#4285F4")!
        }
    }

    var processCommand: ProcessCommand? {
        if case .process(let command) = kind { return command }
        return nil
    }

    static func parse(_ raw: String, shortcuts: [SearchShortcut]) -> InlineCommand? {
        guard let start = raw.firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let end = raw[start...].firstIndex(where: \.isWhitespace) ?? raw.endIndex
        let token = String(raw[start..<end])
        let range = NSRange(start..<end, in: raw)
        let query = String(raw[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = ProcessCommand(rawValue: token.lowercased()) {
            return InlineCommand(kind: .process(command), prefixRange: range, query: query)
        }
        // Single-letter shortcuts are ordinary search text until a space is typed.
        guard end != raw.endIndex else { return nil }
        if let shortcut = shortcuts.first(where: { $0.prefix.caseInsensitiveCompare(token) == .orderedSame }) {
            return InlineCommand(kind: .shortcut(shortcut), prefixRange: range, query: query)
        }
        if token.caseInsensitiveCompare("google") == .orderedSame || token.caseInsensitiveCompare("g") == .orderedSame {
            return InlineCommand(kind: .google, prefixRange: range, query: query)
        }
        return nil
    }
}
