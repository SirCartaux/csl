import AppKit

/// A small, local history of successful web searches. Keystrokes only read the
/// in-memory list; writes occur on a serial utility queue after a successful open.
final class QuerySuggestionHistory {
    static let shared = QuerySuggestionHistory()
    struct Entry: Codable {
        let scope: String
        let query: String
        var uses: Int
        var lastUsed: Date
    }

    private(set) var entries: [Entry]
    private let file: URL
    private let center: NotificationCenter
    private let io = DispatchQueue(label: "com.henri.csl.suggestions", qos: .utility)
    static let limit = 80

    init(file: URL = AppPaths.baseDirectory.appendingPathComponent("search-suggestions.json"),
         center: NotificationCenter = .default) {
        self.file = file
        self.center = center
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(decoded.filter { !$0.query.isEmpty && $0.query.count <= 2000 }.prefix(Self.limit))
        } else {
            entries = []
        }
    }

    static func scope(for command: InlineCommand) -> String? {
        switch command.kind {
        case .process: return nil
        case .shortcut(let shortcut): return "shortcut:" + shortcut.id.uuidString
        case .google: return "google"
        }
    }

    func record(scope: String, query raw: String, date: Date = Date()) {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 2000 else { return }
        let previous = entries.first { $0.scope == scope && $0.query.caseInsensitiveCompare(query) == .orderedSame }
        entries.removeAll { $0.scope == scope && $0.query.caseInsensitiveCompare(query) == .orderedSame }
        entries.insert(Entry(scope: scope, query: query, uses: min(1000, (previous?.uses ?? 0) + 1), lastUsed: date), at: 0)
        entries = Array(entries.prefix(Self.limit))
        save()
    }

    func recordSuccessful(_ result: SearchResult, raw: String) {
        guard result.kind == .website, case .open = result.action else { return }
        let completed = result.completion ?? raw
        if let command = InlineCommand.parse(completed, shortcuts: ShortcutStore.shared.shortcuts),
           let scope = Self.scope(for: command) {
            record(scope: scope, query: command.query)
        } else if let query = WebSearchProvider.query(from: completed) {
            record(scope: "google", query: query)
        }
    }

    func matching(scope: String, query: String, limit: Int = 5) -> [String] {
        entries.compactMap { entry -> (Entry, Int)? in
            guard entry.scope == scope else { return nil }
            if query.isEmpty { return (entry, 0) }
            guard entry.query.caseInsensitiveCompare(query) != .orderedSame,
                  let match = FuzzyMatcher.match(query, in: entry.query) else { return nil }
            return (entry, match.score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.uses != $1.0.uses { return $0.0.uses > $1.0.uses }
            return $0.0.lastUsed > $1.0.lastUsed
        }.prefix(limit).map { $0.0.query }
    }

    func clear() {
        entries.removeAll()
        save()
        center.post(name: .cslSuggestionsChanged, object: nil)
    }

    private func save() {
        let snapshot = entries, file = file
        io.async {
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
            } catch { Log.debug("could not save search suggestions: \(error)") }
        }
    }

    func waitForWrites() { io.sync {} }
}

enum SearchSuggestions {
    /// Complete command/website prefixes without activating their providers.
    static func prefixes(for raw: String, shortcuts: [SearchShortcut]) -> [SearchResult] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), text.count <= 80 else { return [] }
        let needle = text.lowercased()
        var results: [SearchResult] = []
        for command in ProcessCommand.allCases where command.rawValue.hasPrefix(needle) {
            results.append(SearchResult(id: "complete:" + command.rawValue, title: "RUNNING APPS",
                subtitle: "SHOW RUNNING APPS · ENTER OR RIGHT TO COMPLETE", kind: .command,
                icon: .glyph(command == .stop ? .quit : .gear), score: 820,
                titleMatch: [],
                action: .complete(command.rawValue + " "),
                shortcut: ShortcutPresentation(prefix: command.label, name: command.label, tint: command.tint)))
        }
        for shortcut in shortcuts where shortcut.prefix.lowercased().hasPrefix(needle) || shortcut.name.lowercased().hasPrefix(needle) {
            results.append(SearchResult(id: "complete:" + shortcut.id.uuidString, title: shortcut.name,
                subtitle: "SEARCH WITH \(shortcut.prefix) · ENTER OR RIGHT TO COMPLETE", kind: .command,
                icon: .glyph(.globe), score: shortcut.prefix.caseInsensitiveCompare(text) == .orderedSame ? 980 : 810,
                titleMatch: [], action: .complete(shortcut.prefix + " "),
                shortcut: ShortcutPresentation(prefix: shortcut.prefix, name: shortcut.name, tint: shortcut.tint)))
        }
        return results
    }

    static func webResults(command: InlineCommand, raw: String, direct: SearchResult?, history: QuerySuggestionHistory) -> [SearchResult] {
        guard let scope = QuerySuggestionHistory.scope(for: command) else { return [] }
        let prefix = (raw as NSString).substring(with: command.prefixRange)
        let previous = history.matching(scope: scope, query: command.query)
        let suggestions = previous.compactMap { query -> SearchResult? in
            let result: SearchResult?
            switch command.kind {
            case .shortcut(let shortcut):
                guard let url = shortcut.url(for: query) else { return nil }
                result = SearchResult(id: "suggest:" + scope + ":" + query.lowercased(), title: query,
                    subtitle: "RECENT SEARCH · " + shortcut.name.uppercased(), kind: .website, icon: .glyph(.globe),
                    score: 10_000, titleMatch: FuzzyMatcher.match(command.query, in: query)?.ranges ?? [],
                    action: .open(url), shortcut: ShortcutPresentation(prefix: shortcut.prefix, name: shortcut.name, tint: shortcut.tint),
                    completion: prefix + " " + query)
            case .google:
                guard let google = WebSearchProvider.result(for: "google " + query) else { return nil }
                result = SearchResult(id: "suggest:google:" + query.lowercased(), title: query,
                    subtitle: "RECENT SEARCH · GOOGLE", kind: .website, icon: .glyph(.globe), score: 10_000,
                    titleMatch: FuzzyMatcher.match(command.query, in: query)?.ranges ?? [], action: google.action,
                    shortcut: ShortcutPresentation(prefix: prefix.uppercased(), name: "Google", tint: command.tint),
                    completion: prefix + " " + query)
            case .process: return nil
            }
            return result
        }
        // Typing a query and pressing Enter keeps its established exact-search
        // meaning. Tab can then select the first suggestion and browse downward.
        return (direct.map { [$0] } ?? []) + suggestions
    }
}

extension Notification.Name {
    static let cslSuggestionsChanged = Notification.Name("csl.suggestionsChanged")
}
