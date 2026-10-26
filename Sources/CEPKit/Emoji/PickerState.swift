import Foundation

struct RecentEntry: Codable, Hashable {
    var text: String
    var uses: Int
    var lastUsed: TimeInterval
}

struct PickerState: Codable {
    var recents: [RecentEntry] = []
    var favorites: [String] = []
    var skinTone: Int = 0
    var lastCategory: String = PickerCategory.recent.rawValue
    /// Fast lookup is rebuilt from `favorites` on load, not persisted.
    var favoriteLookup: Set<String> = []

    enum CodingKeys: String, CodingKey {
        case recents, favorites, skinTone, lastCategory
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recents = (try? container.decode([RecentEntry].self, forKey: .recents)) ?? []
        favorites = (try? container.decode([String].self, forKey: .favorites)) ?? []
        skinTone = min(max((try? container.decode(Int.self, forKey: .skinTone)) ?? 0, 0), 5)
        lastCategory = (try? container.decode(String.self, forKey: .lastCategory))
            ?? PickerCategory.recent.rawValue
        favoriteLookup = Set(favorites)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recents, forKey: .recents)
        try container.encode(favorites, forKey: .favorites)
        try container.encode(skinTone, forKey: .skinTone)
        try container.encode(lastCategory, forKey: .lastCategory)
    }
}
