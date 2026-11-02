import Foundation

/// A user-defined search word for an app or file. Aliases are stored by target
/// path and become first-class launcher results.
struct SearchAlias: Codable, Identifiable, Equatable {
    let id: UUID
    let alias: String
    let targetPath: String
    let targetName: String
    let isApplication: Bool
    let createdAt: Date

    var targetURL: URL {
        URL(fileURLWithPath: targetPath)
    }

    var targetExists: Bool {
        FileManager.default.fileExists(atPath: targetPath)
    }
}
