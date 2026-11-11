import AppKit

/// Persistent website search shortcuts. The defaults are seeded once; a user
/// can edit the list in Settings.
final class ShortcutStore {
    static let shared = ShortcutStore()

    private(set) var shortcuts: [SearchShortcut] = []
    private var loaded = false

    private init() {
        load()
    }

    // MARK: - Defaults

    static let defaultShortcuts: [SearchShortcut] = [
        make("G", "Google", "https://www.google.com/search?q={query}", "https://www.google.com", "#4285F4"),
        make("Y", "YouTube", "https://www.youtube.com/results?search_query={query}", "https://www.youtube.com", "#FF0033"),
        make("E", "Epidemic Sound", "https://www.epidemicsound.com/search/?term={query}", "https://www.epidemicsound.com", "#FF4F00"),
        make("GB", "Google Bilder", "https://www.google.com/search?tbm=isch&q={query}", "https://www.google.com", "#34A853"),
        make("X", "X", "https://x.com/search?q={query}", "https://x.com", "#E7E9EA"),
        make("I", "Instagram", "https://www.instagram.com/explore/search/keyword/?q={query}", "https://www.instagram.com", "#E1306C"),
        make("F", "Facebook", "https://www.facebook.com/search/top?q={query}", "https://www.facebook.com", "#1877F2"),
        make("T", "Tidal", "https://listen.tidal.com/search?q={query}", "https://listen.tidal.com", "#00CFFF"),
        make("S", "Spotify", "https://open.spotify.com/search/{query}", "https://open.spotify.com", "#1DB954"),
        make("YM", "YouTube Music", "https://music.youtube.com/search?q={query}", "https://music.youtube.com", "#FF0033"),
        make("A", "Amazon", "https://www.amazon.de/s?k={query}", "https://www.amazon.de", "#FF9900"),
        make("ST", "Steam", "https://store.steampowered.com/search/?term={query}", "https://store.steampowered.com", "#66C0F4"),
        make("TW", "Twitch", "https://www.twitch.tv/search?term={query}", "https://www.twitch.tv", "#9146FF")
    ]

    private static func make(
        _ prefix: String,
        _ name: String,
        _ template: String,
        _ site: String,
        _ tint: String
    ) -> SearchShortcut {
        SearchShortcut(
            id: UUID(),
            prefix: prefix,
            name: name,
            searchTemplate: template,
            siteURL: site,
            tintHex: tint,
            iconFileName: nil
        )
    }

    // MARK: - Persistence

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: AppPaths.shortcutsFile) {
            do {
                shortcuts = try JSONDecoder().decode([SearchShortcut].self, from: data)
                normalize()
                Log.debug("shortcuts loaded: \(shortcuts.count)")
                return
            } catch {
                Log.debug("shortcut decode failed: \(error)")
            }
        }
        shortcuts = Self.defaultShortcuts
        save()
        Log.debug("shortcuts seeded: \(shortcuts.count)")
    }

    private func normalize() {
        shortcuts = shortcuts
            .map { shortcut in
                var copy = shortcut
                copy.prefix = Self.normalizedPrefix(shortcut.prefix)
                copy.name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }
            .filter { !$0.prefix.isEmpty }
            .sorted { $0.prefix.count > $1.prefix.count }
    }

    private func save() {
        AppPaths.prepare()
        do {
            let data = try JSONEncoder().encode(shortcuts)
            try data.write(to: AppPaths.shortcutsFile, options: .atomic)
        } catch {
            Log.debug("shortcut save failed: \(error)")
        }
    }

    private func changed() {
        shortcuts.sort { $0.prefix.count > $1.prefix.count }
        save()
        NotificationCenter.default.post(name: .cslShortcutsChanged, object: nil)
    }

    // MARK: - Editing

    enum AddError: LocalizedError {
        case prefix
        case reserved
        case name
        case url
        case duplicate(String)

        var errorDescription: String? {
            switch self {
            case .reserved: return "STOP and RESTART are reserved for running applications."
            case .prefix: return "Please enter a prefix of 1–6 letters or digits."
            case .name: return "Please enter a name."
            case .url: return "The search URL must contain {query} and be a valid HTTP(S) URL."
            case .duplicate(let prefix): return "The prefix \(prefix) is already in use."
            }
        }
    }

    static func normalizedPrefix(_ raw: String) -> String {
        let letters = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowed = CharacterSet.alphanumerics
        guard !letters.isEmpty,
              letters.count <= 6,
              letters.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "" }
        return letters
    }

    @discardableResult
    func add(prefix rawPrefix: String, name rawName: String, template rawTemplate: String) -> Result<SearchShortcut, AddError> {
        let prefix = Self.normalizedPrefix(rawPrefix)
        guard !prefix.isEmpty else { return .failure(.prefix) }
        guard ProcessCommand(rawValue: prefix.lowercased()) == nil else { return .failure(.reserved) }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.name) }

        let template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard template.range(of: "{query}", options: [.caseInsensitive]) != nil,
              let sampleURL = SearchShortcut(
                  id: UUID(),
                  prefix: prefix,
                  name: name,
                  searchTemplate: template,
                  siteURL: "",
                  tintHex: "#FFC24B",
                  iconFileName: nil
              ).url(for: "test"),
              let scheme = sampleURL.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = sampleURL.host else {
            return .failure(.url)
        }

        guard !shortcuts.contains(where: { $0.prefix == prefix }) else {
            return .failure(.duplicate(prefix))
        }

        let site = "\(scheme)://\(host)"
        let tint = Self.palette[shortcuts.count % Self.palette.count]
        let shortcut = SearchShortcut(
            id: UUID(),
            prefix: prefix,
            name: name,
            searchTemplate: template,
            siteURL: site,
            tintHex: tint,
            iconFileName: nil
        )
        shortcuts.append(shortcut)
        changed()
        return .success(shortcut)
    }

    func remove(id: UUID) {
        guard shortcuts.contains(where: { $0.id == id }) else { return }
        shortcuts.removeAll { $0.id == id }
        ShortcutIconService.shared.removeIcon(for: id)
        changed()
    }

    private static let palette = [
        "#4285F4", "#FF0033", "#FF4F00", "#34A853", "#E1306C",
        "#1877F2", "#00CFFF", "#1DB954", "#FF9900", "#66C0F4", "#9146FF"
    ]

    // MARK: - Search

    func match(_ rawQuery: String) -> (shortcut: SearchShortcut, query: String)? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let split = trimmed.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let prefix = String(trimmed[..<split]).uppercased()
        let rest = String(trimmed[split...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, !rest.isEmpty else { return nil }
        guard let shortcut = shortcuts.first(where: { $0.prefix == prefix }) else { return nil }
        return (shortcut, rest)
    }

    func result(for rawQuery: String) -> SearchResult? {
        guard let (shortcut, query) = match(rawQuery),
              let url = shortcut.url(for: query) else { return nil }
        let icon: ResultIcon
        if let iconURL = ShortcutIconService.shared.iconURL(for: shortcut) {
            icon = .image(iconURL)
        } else {
            icon = .glyph(.globe)
        }
        return SearchResult(
            id: "shortcut:" + shortcut.id.uuidString,
            title: shortcut.name.uppercased(),
            subtitle: "SEARCH · \(query)",
            kind: .website,
            icon: icon,
            score: 10_000,
            titleMatch: [],
            action: .open(url),
            shortcut: ShortcutPresentation(
                prefix: shortcut.prefix,
                name: shortcut.name,
                tint: shortcut.tint
            ),
            completion: shortcut.prefix + " " + query
        )
    }
}
