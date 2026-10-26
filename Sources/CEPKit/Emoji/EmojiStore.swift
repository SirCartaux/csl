import AppKit
import QuartzCore

/// Loads the generated emoji database and owns recents, favorites and the
/// selected skin tone. Everything runs on the main thread; the dataset is
/// decoded once at launch (≈880 KiB JSON) before the panel is pre-warmed.
final class EmojiStore {
    static let shared = EmojiStore()

    private(set) var emojiItems: [EmojiItem] = []
    private(set) var symbolItems: [EmojiItem] = []
    private(set) var kaomojiItems: [EmojiItem] = []
    private(set) var allItems: [EmojiItem] = []
    private(set) var state = PickerState()
    private(set) var isLoaded = false

    private var itemsByText: [String: EmojiItem] = [:]
    private var itemsByGroup: [String: [EmojiItem]] = [:]
    private var searchEntries: [SearchEntry] = []
    private var saveWork: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "com.henri.cep.state", qos: .utility)
    private(set) var loadError: String?

    var onStateChange: (() -> Void)?

    private struct SearchEntry {
        let item: EmojiItem
        let haystack: String
        let names: [String]
        let keywordBlob: String
    }

    private init() {}

    // MARK: - Loading

    func load() {
        guard !isLoaded else { return }
        let started = CACurrentMediaTime()

        guard let url = Self.dataURL() else {
            loadError = "emoji.json not found"
            Log.always("CEP: emoji.json not found")
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let payload = try JSONDecoder().decode(EmojiPayload.self, from: data)
            Log.debug(String(format: "json decoded in %.1f ms", (CACurrentMediaTime() - started) * 1000))

            emojiItems = payload.emoji.enumerated().map { index, record in
                record.item(kind: .emoji, index: index)
            }
            let symbolOffset = emojiItems.count
            symbolItems = payload.symbols.enumerated().map { index, record in
                record.item(kind: .symbol, index: symbolOffset + index)
            }
            let kaomojiOffset = symbolOffset + symbolItems.count
            kaomojiItems = payload.kaomoji.enumerated().map { index, record in
                record.item(kind: .kaomoji, index: kaomojiOffset + index)
            }

            allItems = emojiItems + symbolItems + kaomojiItems
            for item in allItems {
                itemsByText[item.text] = item
                itemsByGroup[item.group, default: []].append(item)
            }
            Log.debug(String(format: "items mapped in %.1f ms", (CACurrentMediaTime() - started) * 1000))

            searchEntries = allItems.map { item in
                let raw = [
                    item.name,
                    item.germanName ?? "",
                    item.keywords.replacingOccurrences(of: "|", with: " "),
                    item.subgroup,
                    item.group,
                    item.text
                ].joined(separator: " ")
                let search = SearchText.combined(raw)

                var nameTexts = [item.name]
                if let german = item.germanName, !german.isEmpty {
                    nameTexts.append(german)
                }
                var names: [String] = []
                for text in nameTexts {
                    names.append(text.lowercased())
                    names.append(SearchText.fold(text))
                    names.append(SearchText.transliterate(text))
                }

                let keywordBlob = "|" + item.keywords.lowercased() + "|"
                return SearchEntry(
                    item: item,
                    haystack: search,
                    names: names,
                    keywordBlob: keywordBlob
                )
            }

            Log.debug(String(format: "search index in %.1f ms", (CACurrentMediaTime() - started) * 1000))
            loadState()
            isLoaded = true
            let elapsed = (CACurrentMediaTime() - started) * 1000
            Log.debug(String(
                format: "emoji loaded: %d emoji, %d symbols, %d kaomoji in %.1f ms",
                emojiItems.count, symbolItems.count, kaomojiItems.count, elapsed
            ))
        } catch {
            loadError = error.localizedDescription
            isLoaded = true
            Log.always("CEP: emoji load failed: \(error)")
        }
    }

    private static func dataURL() -> URL? {
        var candidates: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CEP_EMOJI_PATH"], !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: custom))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("emoji.json"))
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/emoji.json")
        )
        if let executable = Bundle.main.executableURL {
            let directory = executable.deletingLastPathComponent()
            candidates.append(directory.appendingPathComponent("Resources/emoji.json"))
            candidates.append(
                directory.deletingLastPathComponent()
                    .appendingPathComponent("Resources/emoji.json")
            )
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - State

    private func loadState() {
        guard let data = try? Data(contentsOf: AppPaths.stateFile),
              let decoded = try? JSONDecoder().decode(PickerState.self, from: data) else {
            state = PickerState()
            return
        }
        state = decoded
        state.skinTone = min(max(state.skinTone, 0), 5)
        state.favorites = state.favorites.filter { itemsByText[$0] != nil }
        state.recents = state.recents.filter { itemsByText[$0.text] != nil }
        state.favoriteLookup = Set(state.favorites)
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeState() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func flush() {
        saveWork?.cancel()
        saveWork = nil
        writeState()
    }

    private func writeState() {
        let snapshot = state
        let url = AppPaths.stateFile
        saveQueue.async {
            do {
                AppPaths.prepare()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.debug("state save failed: \(error)")
            }
        }
    }

    // MARK: - Categories

    func items(for category: PickerCategory) -> [EmojiItem] {
        switch category {
        case .recent:
            return recentItems
        case .favorites:
            return favoriteItems
        case .kaomoji:
            return kaomojiItems
        case .symbols:
            return itemsByGroup["symbols"] ?? []
        default:
            guard let group = category.groupName else { return [] }
            return itemsByGroup[group] ?? []
        }
    }

    func count(for category: PickerCategory) -> Int {
        items(for: category).count
    }

    var recentItems: [EmojiItem] {
        state.recents.prefix(120).compactMap { itemsByText[$0.text] }
    }

    var favoriteItems: [EmojiItem] {
        state.favorites.compactMap { itemsByText[$0] }
    }

    var isStateLoaded: Bool { isLoaded }

    // MARK: - Usage

    func recordUse(_ item: EmojiItem) {
        if let index = state.recents.firstIndex(where: { $0.text == item.text }) {
            state.recents[index].uses += 1
            state.recents[index].lastUsed = Date().timeIntervalSince1970
        } else {
            state.recents.insert(
                RecentEntry(text: item.text, uses: 1, lastUsed: Date().timeIntervalSince1970),
                at: 0
            )
        }
        state.recents.sort { $0.lastUsed > $1.lastUsed }
        if state.recents.count > 80 {
            state.recents = Array(state.recents.prefix(80))
        }
        scheduleSave()
        onStateChange?()
    }

    func isFavorite(_ item: EmojiItem) -> Bool {
        state.favoriteLookup.contains(item.text)
    }

    func toggleFavorite(_ item: EmojiItem) {
        if state.favoriteLookup.contains(item.text) {
            state.favorites.removeAll { $0 == item.text }
            state.favoriteLookup.remove(item.text)
        } else {
            state.favorites.append(item.text)
            state.favoriteLookup.insert(item.text)
        }
        scheduleSave()
        onStateChange?()
    }

    // MARK: - Skin tone

    var skinTone: Int { state.skinTone }

    func setSkinTone(_ tone: Int) {
        let clamped = min(max(tone, 0), 5)
        guard clamped != state.skinTone else { return }
        state.skinTone = clamped
        scheduleSave()
        onStateChange?()
    }

    func insertionText(for item: EmojiItem) -> String {
        item.insertionText(skinTone: state.skinTone)
    }

    // MARK: - Category persistence

    var lastCategory: PickerCategory {
        PickerCategory(rawValue: state.lastCategory) ?? .recent
    }

    func setLastCategory(_ category: PickerCategory) {
        guard state.lastCategory != category.rawValue else { return }
        state.lastCategory = category.rawValue
        scheduleSave()
    }

    func preferredCategory() -> PickerCategory {
        if lastCategory == .recent, state.recents.isEmpty {
            return .smileys
        }
        if lastCategory == .favorites, state.favorites.isEmpty {
            return .smileys
        }
        return lastCategory
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 600) -> [EmojiItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = SearchText.tokens(trimmed)
        guard !tokens.isEmpty else { return [] }

        var tokenVariants: [(String, [String])] = []
        for token in tokens {
            let variants = SearchText.variants(token)
            guard !variants.isEmpty else { continue }
            tokenVariants.append((token, variants))
        }
        guard !tokenVariants.isEmpty else { return [] }

        let favoriteLookup = state.favoriteLookup
        var recentBoost: [String: Int] = [:]
        for entry in state.recents {
            recentBoost[entry.text] = min(40, entry.uses * 5)
        }

        var hits: [(item: EmojiItem, score: Int)] = []
        hits.reserveCapacity(128)

        for entry in searchEntries {
            var score = 0
            var matchedAll = true
            for (_, variants) in tokenVariants {
                var best = 0
                for variant in variants {
                    if entry.keywordBlob.contains("|" + variant + "|") {
                        best = max(best, 1000)
                    }
                    for name in entry.names {
                        if name == variant {
                            best = max(best, 1200)
                        } else if name.hasPrefix(variant) {
                            best = max(best, 880)
                        } else if name.contains(variant) {
                            best = max(best, 640)
                        }
                    }
                    if best < 320, entry.haystack.contains(variant) {
                        best = 320
                    }
                }
                if best == 0 {
                    matchedAll = false
                    break
                }
                score += best
            }
            guard matchedAll else { continue }

            if entry.item.text == trimmed {
                score += 2400
            }
            if favoriteLookup.contains(entry.item.text) {
                score += 50
            }
            if let boost = recentBoost[entry.item.text] {
                score += boost
            }
            hits.append((entry.item, score))
        }

        hits.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.item.sortIndex < $1.item.sortIndex
        }
        return hits.prefix(limit).map(\.item)
    }

    // MARK: - Diagnostics

    func diagnostics() -> String {
        """
        loaded=\(isLoaded) error=\(loadError ?? "none")
        emoji=\(emojiItems.count) symbols=\(symbolItems.count) kaomoji=\(kaomojiItems.count)
        recents=\(state.recents.count) favorites=\(state.favorites.count) skinTone=\(state.skinTone)
        categories=\(PickerCategory.allCases.map { "\($0.rawValue):\(count(for: $0))" }.joined(separator: " "))
        """
    }
}
