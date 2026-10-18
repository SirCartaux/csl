import Foundation

struct FuzzyMatch {
    let score: Int
    let ranges: [NSRange]
}

/// Matching tuned for a launcher:
/// exact > prefix > word-prefix > substring > subsequence.
/// Ranges are UTF-16 offsets so they can be used directly for highlighting.
enum FuzzyMatcher {
    static func match(_ needle: String, in haystack: String) -> FuzzyMatch? {
        let needleLower = needle.lowercased()
        guard !needleLower.isEmpty else { return FuzzyMatch(score: 0, ranges: []) }
        guard !haystack.isEmpty else { return nil }

        let n = needleLower as NSString
        let h = haystack.lowercased() as NSString
        let length = h.length
        guard n.length <= length else { return nil }

        let lengthPenalty = min(90, (length - n.length) * 3)

        if h.isEqual(to: needleLower) {
            return FuzzyMatch(score: 1000, ranges: [NSRange(location: 0, length: length)])
        }

        if h.hasPrefix(needleLower) {
            return FuzzyMatch(score: 900 - lengthPenalty, ranges: [NSRange(location: 0, length: n.length)])
        }

        // Any word boundary: "code" matches "Visual Studio Code".
        var searchStart = 0
        while searchStart < length {
            let found = h.range(of: needleLower, options: [], range: NSRange(location: searchStart, length: length - searchStart))
            guard found.location != NSNotFound else { break }
            if found.location > 0 {
                let previous = h.character(at: found.location - 1)
                let isWordCharacter = (previous >= 48 && previous <= 57)
                    || (previous >= 65 && previous <= 90)
                    || (previous >= 97 && previous <= 122)
                if !isWordCharacter {
                    return FuzzyMatch(score: 820 - lengthPenalty, ranges: [found])
                }
            }
            searchStart = found.location + max(1, found.length)
        }

        let substringRange = h.range(of: needleLower)
        if substringRange.location != NSNotFound {
            let positionPenalty = min(140, substringRange.location * 3)
            return FuzzyMatch(score: 720 - positionPenalty - lengthPenalty, ranges: [substringRange])
        }

        // Subsequence fallback: "vsco" still finds "Visual Studio Code".
        var positions: [Int] = []
        var cursor = 0
        for index in 0..<n.length {
            let target = n.character(at: index)
            var found = -1
            var scan = cursor
            while scan < length {
                if h.character(at: scan) == target {
                    found = scan
                    break
                }
                scan += 1
            }
            guard found >= 0 else { return nil }
            positions.append(found)
            cursor = found + 1
        }

        let span = (positions.last ?? 0) - (positions.first ?? 0) + 1
        let gaps = span - n.length
        let score = max(120, 430 - gaps * 4 - lengthPenalty)
        return FuzzyMatch(score: score, ranges: coalesce(positions))
    }

    private static func coalesce(_ positions: [Int]) -> [NSRange] {
        guard let first = positions.first else { return [] }
        var ranges: [NSRange] = []
        var start = first
        var previous = first

        for position in positions.dropFirst() {
            if position == previous + 1 {
                previous = position
            } else {
                ranges.append(NSRange(location: start, length: previous - start + 1))
                start = position
                previous = position
            }
        }
        ranges.append(NSRange(location: start, length: previous - start + 1))
        return ranges
    }
}
