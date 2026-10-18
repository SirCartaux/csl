import AppKit

/// Matches user-added websites against the query. Everything is in memory, so
/// website results are part of the instant batch.
final class WebsiteProvider {
    func results(for query: String, limit: Int = 4) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        var matches: [SearchResult] = []
        for site in SettingsStore.shared.settings.websites {
            guard let url = site.urlValue else { continue }

            var best: FuzzyMatch?
            var titleRanges: [NSRange] = []

            if let match = FuzzyMatcher.match(query, in: site.displayTitle) {
                best = match
                titleRanges = match.ranges
            }
            if let hostMatch = FuzzyMatcher.match(query, in: site.host) {
                if best == nil || hostMatch.score > best!.score {
                    best = hostMatch
                    titleRanges = []
                }
            }

            guard let match = best else { continue }

            let icon: ResultIcon
            if let iconURL = FaviconService.shared.iconURL(for: site) {
                icon = .image(iconURL)
            } else {
                icon = .glyph(.globe)
            }

            matches.append(SearchResult(
                id: "web:" + site.id.uuidString,
                title: site.displayTitle,
                subtitle: site.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WEBSITE" : site.host,
                kind: .website,
                icon: icon,
                score: min(match.score, 960) + 40,
                titleMatch: titleRanges,
                action: .open(url)
            ))
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        return Array(matches.prefix(limit))
    }
}
