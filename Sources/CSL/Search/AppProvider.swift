import AppKit

struct AppEntry {
    let name: String
    let url: URL
    let folder: String
}

/// Scans the usual application folders once at launch and keeps the result in
/// memory. Matching a few hundred names is effectively instant, so apps can be
/// shown on the very same run-loop tick as the keystroke.
final class AppProvider {
    private(set) var entries: [AppEntry] = []
    private var isLoading = false
    private(set) var isReady = false

    func warmUp(completion: (() -> Void)? = nil) {
        if isReady {
            completion?()
            return
        }
        guard !isLoading else { return }
        isLoading = true

        var roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
            "/System/Cryptexes/App/System/Applications",
            "/System/Library/CoreServices/Applications"
        ]
        roots.append(NSHomeDirectory() + "/Applications")

        DispatchQueue.global(qos: .userInitiated).async {
            let started = CFAbsoluteTimeGetCurrent()
            var found: [String: AppEntry] = [:]
            let fileManager = FileManager.default

            for root in roots {
                let rootURL = URL(fileURLWithPath: root)
                guard let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let url as URL in enumerator {
                    if enumerator.level > 4 {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard url.pathExtension.lowercased() == "app" else { continue }
                    enumerator.skipDescendants()

                    let name = url.deletingPathExtension().lastPathComponent
                    guard !name.isEmpty, !name.hasPrefix(".") else { continue }

                    let entry = AppEntry(
                        name: name,
                        url: url,
                        folder: url.deletingLastPathComponent().path
                    )
                    let key = name.lowercased()
                    if let existing = found[key] {
                        // Prefer the copy in /Applications over user copies.
                        if entry.folder == "/Applications" && existing.folder != "/Applications" {
                            found[key] = entry
                        }
                    } else {
                        found[key] = entry
                    }
                }
            }

            let sorted = found.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            DispatchQueue.main.async {
                self.entries = sorted
                self.isReady = true
                self.isLoading = false
                Log.debug(String(
                    format: "app index: %d apps in %.0f ms",
                    sorted.count,
                    (CFAbsoluteTimeGetCurrent() - started) * 1000
                ))
                completion?()
            }
        }
    }

    func results(for query: String, limit: Int = 12) -> [SearchResult] {
        guard !query.isEmpty, !entries.isEmpty else { return [] }

        var matches: [SearchResult] = []
        for entry in entries {
            guard let match = FuzzyMatcher.match(query, in: entry.name) else { continue }
            matches.append(SearchResult(
                id: "app:" + entry.url.path,
                title: entry.name,
                subtitle: PathDisplay.pretty(entry.folder),
                kind: .application,
                icon: .file(entry.url),
                score: match.score + 60,
                titleMatch: match.ranges,
                action: .open(entry.url)
            ))
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.title.count < $1.title.count
        }
        return Array(matches.prefix(limit))
    }
}
