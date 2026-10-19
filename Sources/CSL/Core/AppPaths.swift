import Foundation

/// Where CSL keeps its settings, index and website icons.
/// `CSL_DATA_DIR` lets the test/demo modes run against a scratch directory.
enum AppPaths {
    static var baseDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CSL_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("CSL", isDirectory: true)
    }

    static var settingsFile: URL { baseDirectory.appendingPathComponent("settings.json") }
    static var indexFile: URL { baseDirectory.appendingPathComponent("index.json") }
    static var rankingFile: URL { baseDirectory.appendingPathComponent("ranking.json") }
    static var iconsDirectory: URL { baseDirectory.appendingPathComponent("icons", isDirectory: true) }
    static var clipboardDirectory: URL { baseDirectory.appendingPathComponent("clipboard", isDirectory: true) }
    static var clipboardBlobsDirectory: URL { clipboardDirectory.appendingPathComponent("blobs", isDirectory: true) }
    static var clipboardIndexFile: URL { clipboardDirectory.appendingPathComponent("history.json") }

    static func prepare() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
    }

    static func prepareClipboard() {
        let fm = FileManager.default
        try? fm.createDirectory(at: clipboardDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: clipboardBlobsDirectory, withIntermediateDirectories: true)
    }
}

extension Notification.Name {
    static let cslSettingsChanged = Notification.Name("csl.settingsChanged")
    static let cslOpenSettings = Notification.Name("csl.openSettings")
    static let cslIndexProgress = Notification.Name("csl.indexProgress")
    static let cslIndexStateChanged = Notification.Name("csl.indexStateChanged")
    static let cslIndexFinished = Notification.Name("csl.indexFinished")
    static let cslIndexChanged = Notification.Name("csl.indexChanged")
    static let cslIndexLoaded = Notification.Name("csl.indexLoaded")
    static let cslWebsiteIconUpdated = Notification.Name("csl.websiteIconUpdated")
    static let cslClipboardChanged = Notification.Name("csl.clipboardChanged")
    static let cslOpenClipboardHistory = Notification.Name("csl.openClipboardHistory")
}
