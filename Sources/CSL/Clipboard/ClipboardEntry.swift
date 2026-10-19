import Foundation

enum ClipboardEntryKind: String, Codable {
    case text
    case link
    case image
    case files

    var label: String {
        switch self {
        case .text: return "TEXT"
        case .link: return "LINK"
        case .image: return "IMAGE"
        case .files: return "FILES"
        }
    }
}

struct ClipboardEntry: Codable, Identifiable {
    let id: UUID
    var kind: ClipboardEntryKind
    var createdAt: Date
    var fingerprint: String
    var pinned: Bool
    var text: String?
    var filePaths: [String]?
    var blobName: String?
    var byteSize: Int
    var sourceApp: String?
    var imageWidth: Int?
    var imageHeight: Int?

    var title: String {
        switch kind {
        case .text, .link:
            let first = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let compact = first.replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return compact.isEmpty ? kind.label : compact
        case .image:
            if let w = imageWidth, let h = imageHeight { return "IMAGE  \(w) × \(h)" }
            return "IMAGE"
        case .files:
            guard let paths = filePaths, !paths.isEmpty else { return "FILES" }
            let name = URL(fileURLWithPath: paths[0]).lastPathComponent
            return paths.count > 1 ? "\(name)  +\(paths.count - 1)" : name
        }
    }

    var subtitle: String {
        switch kind {
        case .text:
            let flattened = (text ?? "").replacingOccurrences(of: "\n", with: "  ·  ")
            return flattened.count > 240 ? String(flattened.prefix(240)) + "…" : flattened
        case .link:
            return text ?? ""
        case .image:
            return "IMAGE FROM CLIPBOARD"
        case .files:
            let paths = filePaths ?? []
            if paths.count == 1 { return paths[0] }
            return paths.prefix(3).joined(separator: "   ·   ")
        }
    }

    var searchText: String {
        ([title, subtitle, sourceApp ?? ""] + (filePaths ?? []))
            .joined(separator: " ")
            .lowercased()
    }

    var imageURL: URL? {
        guard kind == .image, let blobName else { return nil }
        return AppPaths.clipboardBlobsDirectory.appendingPathComponent(blobName)
    }
}
