import Foundation

/// Where CEP keeps its recents, favorites and preferences.
/// `CEP_DATA_DIR` lets tests and demos run against a scratch directory.
enum AppPaths {
    static var baseDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CEP_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("CSL", isDirectory: true)
            .appendingPathComponent("character-picker", isDirectory: true)
    }

    static var stateFile: URL { baseDirectory.appendingPathComponent("state.json") }

    static func prepare() {
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
