import Foundation
import Darwin

struct WebsiteEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var iconFileName: String?

    var urlValue: URL? { URL(string: url) }

    var host: String {
        guard let host = urlValue?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? host : title
    }
}

struct CSLSettings: Codable {
    var version: Int = 1
    var indexedFolders: [String] = []
    var ignoredFolders: [String] = []
    var ignoredExtensions: [String] = []
    var websites: [WebsiteEntry] = []
    var launcherScale: Double? = nil
    var pixelAnimationSpeed: Double? = nil
    var pixelAnimationSpeedV2: Double? = nil
    var resultGlowEnabled: Bool? = nil
    var resultGlowIntensity: Double? = nil
    var resultGlowDuration: Double? = nil
}

/// Single source of truth for user preferences. Persisted as JSON in
/// ~/Library/Application Support/CSL/settings.json.
final class SettingsStore {
    static let shared = SettingsStore()

    static let defaultPixelAnimationSpeed: Double = 1.0
    static let minPixelAnimationSpeed: Double = 0.25
    static let maxPixelAnimationSpeed: Double = 2.0
    /// The 1.0 speed keeps the timing the app had when the slider read 0.5.
    static let pixelAnimationBaseScale: Double = 2.55

    private(set) var settings: CSLSettings
    private var ignoredExtensionSet: Set<String> = []

    private init() {
        AppPaths.prepare()
        settings = Self.load()
        rebuildCaches()
    }

    // MARK: - Persistence

    private static func load() -> CSLSettings {
        guard let data = try? Data(contentsOf: AppPaths.settingsFile) else {
            return CSLSettings()
        }
        do {
            return try JSONDecoder().decode(CSLSettings.self, from: data)
        } catch {
            Log.debug("settings decode failed: \(error)")
            return CSLSettings()
        }
    }

    func save(notify: Bool = true) {
        rebuildCaches()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: AppPaths.settingsFile, options: .atomic)
        } catch {
            Log.debug("settings save failed: \(error)")
        }
        if notify {
            NotificationCenter.default.post(name: .cslSettingsChanged, object: nil)
        }
    }

    /// Persist the launcher scale without triggering a search refresh while the
    /// user is dragging a window edge.
    func setLauncherScale(_ value: Double) {
        let clamped = min(max(value, 0.7), 2.2)
        guard settings.launcherScale != clamped else { return }
        settings.launcherScale = clamped
        save(notify: false)
    }

    /// Animation speed multiplies the visual timing (1.0 = old speed,
    /// lower = slower). Persisting it never refreshes the search engine.
    var pixelAnimationSpeed: Double {
        let value = settings.pixelAnimationSpeedV2 ?? Self.defaultPixelAnimationSpeed
        return min(max(value, Self.minPixelAnimationSpeed), Self.maxPixelAnimationSpeed)
    }

    func setPixelAnimationSpeed(_ value: Double) {
        let clamped = min(max(value, Self.minPixelAnimationSpeed), Self.maxPixelAnimationSpeed)
        guard abs(pixelAnimationSpeed - clamped) > 0.0001 else { return }
        settings.pixelAnimationSpeedV2 = clamped
        save(notify: false)
    }

    var resultGlowEnabled: Bool {
        settings.resultGlowEnabled ?? true
    }

    var resultGlowIntensity: Double {
        min(max(settings.resultGlowIntensity ?? 0.55, 0.1), 1.0)
    }

    var resultGlowDuration: Double {
        min(max(settings.resultGlowDuration ?? 0.30, 0.12), 0.8)
    }

    func setResultGlowEnabled(_ enabled: Bool) {
        guard resultGlowEnabled != enabled else { return }
        settings.resultGlowEnabled = enabled
        save(notify: false)
    }

    func setResultGlowIntensity(_ value: Double) {
        let clamped = min(max(value, 0.1), 1.0)
        guard abs(resultGlowIntensity - clamped) > 0.0001 else { return }
        settings.resultGlowIntensity = clamped
        save(notify: false)
    }

    func setResultGlowDuration(_ value: Double) {
        let clamped = min(max(value, 0.12), 0.8)
        guard abs(resultGlowDuration - clamped) > 0.0001 else { return }
        settings.resultGlowDuration = clamped
        save(notify: false)
    }

    private func rebuildCaches() {
        ignoredExtensionSet = Set(settings.ignoredExtensions.map { $0.lowercased() })
    }

    // MARK: - Folders

    static func normalizeFolder(_ path: String) -> String {
        // realpath() keeps /tmp and /private/tmp (and similar aliases) aligned
        // with the paths FileManager returns while indexing.
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(standardized, &buffer) != nil {
            return String(cString: buffer)
        }
        if standardized.count > 1, standardized.hasSuffix("/") {
            return String(standardized.dropLast())
        }
        return standardized
    }

    @discardableResult
    func addIndexedFolder(_ path: String) -> Bool {
        let folder = Self.normalizeFolder(path)
        guard !settings.indexedFolders.contains(folder) else { return false }

        settings.ignoredFolders.removeAll { $0 == folder }
        settings.indexedFolders.append(folder)
        settings.indexedFolders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        save()
        return true
    }

    func removeIndexedFolder(_ folder: String) {
        settings.indexedFolders.removeAll { $0 == folder }
        save()
    }

    @discardableResult
    func addIgnoredFolder(_ path: String) -> Bool {
        let folder = Self.normalizeFolder(path)
        guard !settings.ignoredFolders.contains(folder) else { return false }

        settings.indexedFolders.removeAll { $0 == folder }
        settings.ignoredFolders.append(folder)
        settings.ignoredFolders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        save()
        return true
    }

    func removeIgnoredFolder(_ folder: String) {
        settings.ignoredFolders.removeAll { $0 == folder }
        save()
    }

    // MARK: - Extensions

    static func normalizeExtension(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasPrefix(".") {
            value.removeFirst()
        }
        guard !value.isEmpty, value.count <= 16 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "+-"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return value
    }

    /// Accepts "psd, aep  mov" and returns the extensions that were added.
    @discardableResult
    func addIgnoredExtensions(_ raw: String) -> [String] {
        let candidates = raw
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == ";" })
            .compactMap { Self.normalizeExtension(String($0)) }

        var added: [String] = []
        for candidate in candidates where !settings.ignoredExtensions.contains(candidate) {
            settings.ignoredExtensions.append(candidate)
            added.append(candidate)
        }
        if !added.isEmpty {
            settings.ignoredExtensions.sort()
            save()
        }
        return added
    }

    func removeIgnoredExtension(_ ext: String) {
        settings.ignoredExtensions.removeAll { $0 == ext }
        save()
    }

    // MARK: - Websites

    static func normalizedURL(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" ") else { return nil }
        if !value.contains("://") {
            value = "https://" + value
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else { return nil }
        return components.url
    }

    @discardableResult
    func addWebsite(rawURL: String, title: String) -> WebsiteEntry? {
        guard let url = Self.normalizedURL(from: rawURL) else { return nil }
        let absolute = url.absoluteString
        guard !settings.websites.contains(where: { $0.url == absolute }) else { return nil }

        let entry = WebsiteEntry(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            url: absolute,
            iconFileName: nil
        )
        settings.websites.append(entry)
        save()

        FaviconService.shared.fetchIcon(for: entry)
        return entry
    }

    func removeWebsite(id: UUID) {
        guard let entry = settings.websites.first(where: { $0.id == id }) else { return }
        settings.websites.removeAll { $0.id == id }
        FaviconService.shared.removeIcon(for: entry)
        save()
    }

    func updateWebsiteIcon(id: UUID, fileName: String?) {
        guard let index = settings.websites.firstIndex(where: { $0.id == id }) else { return }
        settings.websites[index].iconFileName = fileName
        save()
    }

    func website(id: UUID) -> WebsiteEntry? {
        settings.websites.first { $0.id == id }
    }

    // MARK: - Filters

    func isIgnored(path: String) -> Bool {
        guard !settings.ignoredFolders.isEmpty else { return false }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return Self.path(normalized, isInsideAny: settings.ignoredFolders)
    }

    /// Fast variant for hot loops. Paths from the index and from Spotlight are
    /// already normalized, so no extra URL round-trip is needed.
    func isIgnoredFast(_ path: String) -> Bool {
        Self.path(path, isInsideAny: settings.ignoredFolders)
    }

    static func path(_ path: String, isInsideAny folders: [String]) -> Bool {
        for folder in folders {
            if path == folder { return true }
            if path.hasPrefix(folder + "/") { return true }
        }
        return false
    }

    func isExtensionIgnored(_ ext: String) -> Bool {
        guard !ignoredExtensionSet.isEmpty else { return false }
        var value = ext.lowercased()
        while value.hasPrefix(".") { value.removeFirst() }
        return ignoredExtensionSet.contains(value)
    }
}
