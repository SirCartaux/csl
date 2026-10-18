import AppKit

struct AppEntry {
    /// Canonical (usually English) app name shown in results.
    let name: String
    let url: URL
    let folder: String
    /// Localized names used for matching only.
    let aliases: [String]
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
                        folder: url.deletingLastPathComponent().path,
                        aliases: Self.localizedAliases(for: url, name: name)
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
        let query = Self.cleaned(query)
        guard !query.isEmpty, !entries.isEmpty else { return [] }

        var matches: [SearchResult] = []
        for entry in entries {
            var bestScore = Int.min
            var bestRanges: [NSRange] = []
            var bestIsTitle = false

            let candidates = [entry.name] + entry.aliases
            for candidate in candidates {
                guard let match = FuzzyMatcher.match(query, in: candidate) else { continue }
                let isTitle = candidate == entry.name
                if match.score > bestScore || (match.score == bestScore && isTitle && !bestIsTitle) {
                    bestScore = match.score
                    bestIsTitle = isTitle
                    bestRanges = isTitle ? match.ranges : []
                }
            }
            guard bestScore != Int.min else { continue }

            matches.append(SearchResult(
                id: "app:" + entry.url.path,
                title: entry.name,
                subtitle: PathDisplay.pretty(entry.folder),
                kind: .application,
                icon: .file(entry.url),
                score: bestScore + 60,
                titleMatch: bestRanges,
                action: .open(entry.url)
            ))
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.title.count < $1.title.count
        }
        return Array(matches.prefix(limit))
    }

    // MARK: - Localized names

    private static let preferredLanguageKeys: [String] = {
        var keys: [String] = ["en"]
        for language in Locale.preferredLanguages {
            keys.append(language)
            if let base = language.split(separator: "-").first {
                keys.append(String(base))
            }
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }()

    /// The bundle's localized display name (for example
    /// "Festplattendienstprogramm.app") is not exposed by Bundle for system
    /// apps, but lives in InfoPlist.loctable. Collect it for the current
    /// languages and use it for matching only; the result title stays English.
    private static func localizedAliases(for url: URL, name: String) -> [String] {
        var raw: [String] = []
        let resources = url.appendingPathComponent("Contents/Resources", isDirectory: true)

        let loctable = resources.appendingPathComponent("InfoPlist.loctable")
        if let data = try? Data(contentsOf: loctable),
           let plist = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ) as? [String: [String: Any]] {
            for language in preferredLanguageKeys {
                guard let entry = plist[language] else { continue }
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let value = entry[key] as? String { raw.append(value) }
                }
            }
        }

        if let bundle = Bundle(url: url) {
            for dictionary in [bundle.localizedInfoDictionary, bundle.infoDictionary] {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let value = dictionary?[key] as? String { raw.append(value) }
                }
            }
        }

        for language in preferredLanguageKeys {
            let strings = resources
                .appendingPathComponent("\(language).lproj", isDirectory: true)
                .appendingPathComponent("InfoPlist.strings")
            guard let data = try? Data(contentsOf: strings),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any] else { continue }
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let value = plist[key] as? String { raw.append(value) }
            }
        }

        var seen = Set<String>()
        var aliases: [String] = []
        for value in [name] + raw {
            let cleaned = cleaned(value)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            if seen.insert(key).inserted {
                aliases.append(cleaned)
            }
        }
        return aliases
    }

    private static func cleaned(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x00AD, 0x200B...0x200F, 0xFEFF:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
