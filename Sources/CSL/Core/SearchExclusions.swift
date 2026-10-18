import Foundation

/// Paths that never belong in a launcher result, no matter whether they come
/// from the custom index or from Spotlight: build artifacts, caches, package
/// manager folders and the like.
enum SearchExclusions {
    static let fragments = [
        "/node_modules/",
        "/.git/",
        "/.build/",
        "/build/",
        "/deriveddata/",
        "/index.noindex/",
        "/caches/",
        "/library/",
        "/.trash/",
        "/.venv/",
        "/venv/",
        "/pods/",
        "/target/",
        "/cmake-build-",
        "/.cache/",
        "/.next/"
    ]

    static func isExcluded(_ path: String) -> Bool {
        let lower = path.lowercased()
        for fragment in fragments where lower.contains(fragment) {
            return true
        }
        return false
    }
}
