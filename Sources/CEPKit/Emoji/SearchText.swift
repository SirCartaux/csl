import Foundation

/// Case-, accent- and umlaut-insensitive matching. Every field is indexed in
/// three forms (lowercase, diacritic-folded, German transliterated) so that
/// “grün”, “gruen” and “grun” all find the same emoji.
///
/// Foundation's `folding(options:)` is convenient but expensive when applied
/// to thousands of strings at launch. This implementation builds a small
/// Latin accent table once and then does a single scalar pass per string.
enum SearchText {
    private static let locale = Locale(identifier: "de_DE")

    private struct FoldTable {
        var fold: [Unicode.Scalar: String] = [:]
        var translit: [Unicode.Scalar: String] = [:]
    }

    private static let tables: FoldTable = {
        var tables = FoldTable()

        // Latin-1 Supplement, Latin Extended-A/B and Latin Extended Additional.
        let ranges: [ClosedRange<UInt32>] = [0x00C0...0x024F, 0x1E00...0x1EFF]
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let original = String(scalar)
                let folded = original.folding(
                    options: [.diacriticInsensitive, .widthInsensitive],
                    locale: locale
                )
                if folded != original {
                    tables.fold[scalar] = folded
                }
            }
        }

        let manualFold: [UInt32: String] = [
            0x00DF: "ss", // ß
            0x00E6: "ae", // æ
            0x0153: "oe", // œ
            0x00F8: "o",  // ø
            0x00E5: "a",  // å
            0x0111: "d",  // đ
            0x0142: "l",  // ł
            0x00FE: "th", // þ
            0x00F0: "d"   // ð
        ]
        for (value, replacement) in manualFold {
            if let scalar = Unicode.Scalar(value) {
                tables.fold[scalar] = replacement
            }
        }

        let manualTranslit: [UInt32: String] = [
            0x00E4: "ae", // ä
            0x00F6: "oe", // ö
            0x00FC: "ue", // ü
            0x00DF: "ss", // ß
            0x00E6: "ae", // æ
            0x0153: "oe", // œ
            0x00F8: "oe", // ø
            0x00E5: "aa", // å
            0x0111: "d",  // đ
            0x0142: "l",  // ł
            0x00FE: "th", // þ
            0x00F0: "d"   // ð
        ]
        for (value, replacement) in manualTranslit {
            if let scalar = Unicode.Scalar(value) {
                tables.translit[scalar] = replacement
            }
        }

        return tables
    }()

    static func fold(_ value: String) -> String {
        let lower = value.lowercased()
        var changed = false
        for scalar in lower.unicodeScalars where tables.fold[scalar] != nil {
            changed = true
            break
        }
        guard changed else { return lower }

        var result = String()
        result.reserveCapacity(lower.utf8.count)
        for scalar in lower.unicodeScalars {
            if let mapped = tables.fold[scalar] {
                result.append(mapped)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func transliterate(_ value: String) -> String {
        let lower = value.lowercased()
        var changed = false
        for scalar in lower.unicodeScalars where tables.translit[scalar] != nil || tables.fold[scalar] != nil {
            changed = true
            break
        }
        guard changed else { return lower }

        var result = String()
        result.reserveCapacity(lower.utf8.count)
        for scalar in lower.unicodeScalars {
            if let mapped = tables.translit[scalar] {
                result.append(mapped)
            } else if let mapped = tables.fold[scalar] {
                result.append(mapped)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func variants(_ token: String) -> [String] {
        let raw = token.lowercased()
        var seen = Set<String>()
        return [raw, fold(raw), transliterate(raw)].filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func tokens(_ query: String) -> [String] {
        query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func combined(_ value: String) -> String {
        let lower = value.lowercased()
        return lower + " " + fold(lower) + " " + transliterate(lower)
    }
}
