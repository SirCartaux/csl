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

    private static let directoryNames = Set(fragments.filter { $0.hasSuffix("/") }.map {
        String($0.dropFirst().dropLast())
    })

    static func isExcluded(_ path: String) -> Bool {
        // One component pass instead of seventeen substring searches. Keep the
        // original boundary semantics: /build/ excludes descendants, not a file
        // named "build"; /cmake-build- is deliberately a component prefix.
        let components = path.lowercased().split(separator: "/", omittingEmptySubsequences: false)
        for index in components.indices.dropFirst() {
            let component = components[index]
            if component.hasPrefix("cmake-build-") { return true }
            if index < components.count-1, directoryNames.contains(String(component)) { return true }
        }
        return false
    }
}
