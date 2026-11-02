import AppKit

/// Persistent user aliases. Matching aliases are emitted as high-confidence
/// launcher results and reuse the normal app/file result identity so a target
/// never appears twice.
final class AliasStore {
    static let shared = AliasStore()

    private(set) var aliases: [SearchAlias] = []

    private init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.aliasesFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            aliases = try decoder.decode([SearchAlias].self, from: data)
            sort()
            Log.debug("aliases loaded: \(aliases.count)")
        } catch {
            Log.debug("alias decode failed: \(error)")
            aliases = []
        }
    }

    private func save() {
        AppPaths.prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(aliases)
            try data.write(to: AppPaths.aliasesFile, options: .atomic)
            Log.debug("aliases saved: \(aliases.count)")
        } catch {
            Log.debug("alias save failed: \(error)")
        }
    }

    private func sort() {
        aliases.sort {
            let comparison = $0.alias.localizedCaseInsensitiveCompare($1.alias)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.targetName.localizedCaseInsensitiveCompare($1.targetName) == .orderedAscending
        }
    }

    private func changed() {
        sort()
        save()
        NotificationCenter.default.post(name: .cslAliasesChanged, object: nil)
    }

    // MARK: - Editing

    enum AddError: LocalizedError {
        case empty
        case targetMissing
        case duplicate(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Please enter an alias."
            case .targetMissing:
                return "The selected app or file could not be found."
            case .duplicate(let message):
                return message
            }
        }
    }

    static func normalizedAlias(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func displayName(for url: URL) -> String {
        if url.pathExtension.lowercased() == "app" {
            return url.deletingPathExtension().lastPathComponent
        }
        return url.lastPathComponent
    }

    @discardableResult
    func add(
        alias rawAlias: String,
        targetURL: URL,
        targetName: String? = nil
    ) -> Result<SearchAlias, AddError> {
        let alias = Self.normalizedAlias(rawAlias)
        guard !alias.isEmpty else { return .failure(.empty) }
        guard alias.count <= 80 else {
            return .failure(.duplicate("Aliases can be at most 80 characters."))
        }

        let path = targetURL.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failure(.targetMissing)
        }

        let folded = alias.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        for existing in aliases {
            let existingFolded = existing.alias.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard existingFolded == folded else { continue }
            if existing.targetPath == path {
                return .failure(.duplicate("This item already has the alias “\(alias)”."))
            }
            return .failure(.duplicate("The alias “\(alias)” is already used by \(existing.targetName)."))
        }

        let item = SearchAlias(
            id: UUID(),
            alias: alias,
            targetPath: path,
            targetName: targetName?.isEmpty == false ? targetName! : Self.displayName(for: targetURL),
            isApplication: targetURL.pathExtension.lowercased() == "app",
            createdAt: Date()
        )
        aliases.append(item)
        changed()
        return .success(item)
    }

    func remove(id: UUID) {
        guard aliases.contains(where: { $0.id == id }) else { return }
        aliases.removeAll { $0.id == id }
        changed()
    }

    // MARK: - Search

    func results(for query: String, limit: Int = 8) -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, !aliases.isEmpty else { return [] }

        var best: [String: (alias: SearchAlias, match: FuzzyMatch)] = [:]
        for alias in aliases {
            guard alias.targetExists,
                  let match = FuzzyMatcher.match(needle, in: alias.alias) else { continue }
            let id = (alias.isApplication ? "app:" : "file:") + alias.targetPath
            if let current = best[id], current.match.score >= match.score { continue }
            best[id] = (alias, match)
        }

        return best.values
            .map { entry in
                let url = entry.alias.targetURL
                return SearchResult(
                    id: (entry.alias.isApplication ? "app:" : "file:") + entry.alias.targetPath,
                    title: entry.alias.targetName,
                    subtitle: "ALIAS · \(entry.alias.alias)",
                    kind: entry.alias.isApplication ? .application : .file,
                    icon: .file(url),
                    score: 1000 + entry.match.score,
                    titleMatch: [],
                    action: .open(url)
                )
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }
}
