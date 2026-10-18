import AppKit

/// Small, permission-free helper commands. They make the empty state useful and
/// prove that non-file results flow through the same pipeline.
final class CommandProvider {
    private struct Command {
        let id: String
        let title: String
        let subtitle: String
        let keywords: [String]
        let glyph: PixelGlyph
        let action: ResultAction
        var maxScore: Int? = nil
        var showsWhenEmpty: Bool = true
    }

    private lazy var commands: [Command] = [
        Command(
            id: "cmd:sleep",
            title: "SLEEP",
            subtitle: "SUSPEND THE MAC",
            keywords: ["sleep", "schlaf", "ruhezustand", "standby"],
            glyph: .moon,
            action: .run { Shell.run("/usr/bin/pmset", ["sleepnow"]) }
        ),
        Command(
            id: "cmd:trash",
            title: "EMPTY TRASH",
            subtitle: "DELETE EVERYTHING IN THE BIN",
            keywords: ["empty", "trash", "papierkorb", "leeren", "muell", "müll"],
            glyph: .trash,
            action: .run { Shell.emptyTrash() }
        ),
        Command(
            id: "cmd:screenshot",
            title: "SCREENSHOT",
            subtitle: "CAPTURE AN AREA OF THE SCREEN",
            keywords: ["screenshot", "bildschirmfoto", "capture", "shot"],
            glyph: .camera,
            action: .run { Shell.run("/usr/sbin/screencapture", ["-i"]) }
        ),
        Command(
            id: "cmd:settings",
            title: "SYSTEM SETTINGS",
            subtitle: "OPEN SYSTEM PREFERENCES",
            keywords: ["settings", "einstellungen", "preferences", "system"],
            glyph: .gear,
            action: .open(URL(string: "x-apple.systempreferences:")!)
        ),
        Command(
            id: "cmd:applications",
            title: "APPLICATIONS",
            subtitle: "SHOW THE APPLICATIONS FOLDER",
            keywords: ["applications", "programme", "apps", "folder", "ordner"],
            glyph: .folder,
            action: .open(URL(fileURLWithPath: "/Applications"))
        ),
        Command(
            id: "cmd:quit",
            title: "QUIT CSL",
            subtitle: "STOP THE LAUNCHER",
            keywords: ["quit", "beenden", "exit", "close"],
            glyph: .quit,
            action: .run { NSApp.terminate(nil) }
        ),
        Command(
            id: "cmd:csl-settings",
            title: "CSL SETTINGS",
            subtitle: "INDEX, FILTER, WEBSITES",
            keywords: ["settings", "einstellungen", "preferences", "csl", "konfiguration", "config"],
            glyph: .gear,
            action: .run { NotificationCenter.default.post(name: .cslOpenSettings, object: nil) },
            maxScore: 930,
            showsWhenEmpty: false
        )
    ]

    func allResults() -> [SearchResult] {
        commands.filter(\.showsWhenEmpty).map { result(for: $0, score: 0, ranges: []) }
    }

    func results(for query: String, limit: Int = 4) -> [SearchResult] {
        guard !query.isEmpty else { return allResults() }

        var matches: [SearchResult] = []
        for command in commands {
            var best: FuzzyMatch?
            for keyword in command.keywords {
                if let match = FuzzyMatcher.match(query, in: keyword) {
                    if best == nil || match.score > best!.score { best = match }
                }
            }
            if let match = FuzzyMatcher.match(query, in: command.title) {
                if best == nil || match.score > best!.score { best = match }
            }
            guard let match = best, match.score >= 500 else { continue }

            let ranges = match.ranges.filter { $0.location + $0.length <= (command.title as NSString).length }
            matches.append(result(for: command, score: min(match.score, 920) + 40, ranges: ranges))
        }

        matches.sort { $0.score > $1.score }
        return Array(matches.prefix(limit))
    }

    private func result(for command: Command, score: Int, ranges: [NSRange]) -> SearchResult {
        SearchResult(
            id: command.id,
            title: command.title,
            subtitle: command.subtitle,
            kind: .command,
            icon: .glyph(command.glyph),
            score: min(score, command.maxScore ?? Int.max),
            titleMatch: ranges,
            action: command.action
        )
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            Log.debug("failed to run \(path): \(error)")
            return false
        }
    }

    static func emptyTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: trash,
            includingPropertiesForKeys: nil
        ) else { return }

        for item in items {
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                Log.debug("could not delete \(item.lastPathComponent): \(error)")
            }
        }
    }
}
