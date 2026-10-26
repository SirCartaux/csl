import Foundation

/// One selectable character: an emoji, a typographic symbol or a kaomoji.
struct EmojiItem: Hashable, Identifiable {
    enum Kind: Int, Hashable {
        case emoji
        case symbol
        case kaomoji
    }

    let text: String
    let name: String
    let germanName: String?
    let keywords: String
    let group: String
    let subgroup: String
    let tones: [String]?
    let kind: Kind
    let sortIndex: Int

    var id: String { text }

    var isKaomoji: Bool { kind == .kaomoji }
    var isSymbol: Bool { kind == .symbol }
    var supportsSkinTone: Bool { kind == .emoji && tones != nil }

    var displayName: String {
        name.isEmpty ? text : name
    }

    /// The exact string that should be typed for the selected skin tone.
    func insertionText(skinTone: Int) -> String {
        guard kind == .emoji, let tones, skinTone > 0, skinTone <= tones.count else {
            return text
        }
        let tone = tones[skinTone - 1]
        return tone.isEmpty ? text : tone
    }

    func with(kind: Kind, sortIndex: Int) -> EmojiItem {
        EmojiItem(
            text: text,
            name: name,
            germanName: germanName,
            keywords: keywords,
            group: group,
            subgroup: subgroup,
            tones: tones,
            kind: kind,
            sortIndex: sortIndex
        )
    }
}

// MARK: - JSON records

struct EmojiRecord: Decodable {
    let e: String
    let n: String
    let d: String?
    let k: String
    let g: String
    let sg: String
    let t: [String]?
}

struct EmojiPayload: Decodable {
    let version: Int
    let emoji: [EmojiRecord]
    let symbols: [EmojiRecord]
    let kaomoji: [EmojiRecord]
}

extension EmojiRecord {
    func item(kind: EmojiItem.Kind, index: Int) -> EmojiItem {
        EmojiItem(
            text: e,
            name: n,
            germanName: d,
            keywords: k,
            group: g,
            subgroup: sg,
            tones: t,
            kind: kind,
            sortIndex: index
        )
    }
}

// MARK: - Categories

enum PickerCategory: String, CaseIterable, Codable {
    case recent
    case favorites
    case smileys
    case people
    case nature
    case food
    case activity
    case travel
    case objects
    case symbols
    case flags
    case kaomoji

    var title: String {
        switch self {
        case .recent: return "RECENT"
        case .favorites: return "FAVORITES"
        case .smileys: return "SMILEYS"
        case .people: return "PEOPLE"
        case .nature: return "NATURE"
        case .food: return "FOOD"
        case .activity: return "ACTIVITY"
        case .travel: return "TRAVEL"
        case .objects: return "OBJECTS"
        case .symbols: return "SYMBOLS"
        case .flags: return "FLAGS"
        case .kaomoji: return "KAOMOJI"
        }
    }

    var longTitle: String {
        switch self {
        case .recent: return "RECENTLY USED"
        case .favorites: return "FAVORITES"
        case .smileys: return "SMILEYS & EMOTION"
        case .people: return "PEOPLE & BODY"
        case .nature: return "ANIMALS & NATURE"
        case .food: return "FOOD & DRINK"
        case .activity: return "ACTIVITY"
        case .travel: return "TRAVEL & PLACES"
        case .objects: return "OBJECTS"
        case .symbols: return "SYMBOLS"
        case .flags: return "FLAGS"
        case .kaomoji: return "KAOMOJI"
        }
    }

    /// An emoji used as the category icon in the sidebar.
    var icon: String {
        switch self {
        case .recent: return "🕘"
        case .favorites: return "★"
        case .smileys: return "😀"
        case .people: return "🧑"
        case .nature: return "🐻"
        case .food: return "🍔"
        case .activity: return "⚽"
        case .travel: return "✈️"
        case .objects: return "💡"
        case .symbols: return "♠"
        case .flags: return "🏳️"
        case .kaomoji: return "ツ"
        }
    }

    /// `true` when the category icon should be drawn with a text font instead
    /// of Apple Color Emoji.
    var iconIsText: Bool {
        self == .favorites || self == .symbols || self == .kaomoji
    }

    var supportsSkinTone: Bool {
        switch self {
        case .symbols, .flags, .kaomoji:
            return false
        default:
            return true
        }
    }

    var groupName: String? {
        switch self {
        case .smileys: return "smileys"
        case .people: return "people"
        case .nature: return "nature"
        case .food: return "food"
        case .activity: return "activity"
        case .travel: return "travel"
        case .objects: return "objects"
        case .flags: return "flags"
        default: return nil
        }
    }
}
