import Foundation

/// In-memory LRU cache for the first visible file results of a query.
///
/// The full index scan can be slow on large external volumes. Once a query has
/// produced results, the first screenful is cached: typing the same query again
/// paints those rows immediately while the full index search refreshes in the
/// background. Scrolling beyond the cached rows still waits for the full scan.
final class FileResultCache {
    static let shared = FileResultCache()

    private struct CachedResult {
        let path: String
        let title: String
        let subtitle: String
        let score: Int
        let titleMatch: [NSRange]
    }

    private struct Entry {
        let results: [CachedResult]
        let cost: Int
    }

    private let maxBytes = 30 * 1024 * 1024
    private let visibleLimit = 7
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var totalBytes = 0

    private init() {}

    func results(for query: String) -> [SearchResult] {
        let key = normalize(query)
        guard !key.isEmpty, let entry = entries[key] else { return [] }
        touch(key)
        Log.debug("file cache: hit \(entry.results.count) for \"\(key)\"")
        return entry.results.map { cached in
            let url = URL(fileURLWithPath: cached.path)
            return SearchResult(
                id: "file:" + cached.path,
                title: cached.title,
                subtitle: cached.subtitle,
                kind: .file,
                icon: .file(url),
                score: cached.score,
                titleMatch: cached.titleMatch,
                action: .open(url)
            )
        }
    }

    func store(_ results: [SearchResult], for query: String) {
        let key = normalize(query)
        guard !key.isEmpty else { return }

        var seen = Set<String>()
        var cached: [CachedResult] = []
        for result in results {
            guard cached.count < visibleLimit else { break }
            guard case .file = result.kind else { continue }
            guard result.id.hasPrefix("file:") else { continue }
            let path = String(result.id.dropFirst("file:".count))
            guard seen.insert(path).inserted else { continue }
            cached.append(CachedResult(
                path: path,
                title: result.title,
                subtitle: result.subtitle,
                score: result.score,
                titleMatch: result.titleMatch
            ))
        }
        guard !cached.isEmpty else { return }

        let cost = estimateCost(key: key, results: cached)
        guard cost < maxBytes else { return }

        if let old = entries.removeValue(forKey: key) {
            totalBytes -= old.cost
            order.removeAll { $0 == key }
        }
        entries[key] = Entry(results: cached, cost: cost)
        order.append(key)
        totalBytes += cost
        evictIfNeeded()
        Log.debug("file cache: stored \(cached.count) for \"\(key)\" (\(totalBytes / 1024) KB total)")
    }

    private func touch(_ key: String) {
        guard entries[key] != nil else { return }
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictIfNeeded() {
        while totalBytes > maxBytes, let oldest = order.first {
            order.removeFirst()
            if let entry = entries.removeValue(forKey: oldest) {
                totalBytes -= entry.cost
            }
        }
    }

    private func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func estimateCost(key: String, results: [CachedResult]) -> Int {
        var bytes = key.utf8.count + 96
        for result in results {
            bytes += result.path.utf8.count
            bytes += result.title.utf8.count
            bytes += result.subtitle.utf8.count
            bytes += result.titleMatch.count * 16
            bytes += 128
        }
        return bytes
    }
}
