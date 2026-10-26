import AppKit
import CoreText

/// Loads the bundled Silkscreen pixel font and vends sized instances.
/// Falls back to the system monospaced font if registration fails.
enum PixelFont {
    static let regularName = "Silkscreen-Regular"
    static let boldName = "Silkscreen-Bold"

    private static var didRegister = false
    private static var cache: [String: NSFont] = [:]

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Fonts"))
            candidates.append(resources)
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Fonts")
        )
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("Resources/Fonts"))
        }

        for directory in candidates {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }

            for file in files where file.pathExtension.lowercased() == "ttf" {
                var error: Unmanaged<CFError>?
                let ok = CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error)
                if !ok {
                    Log.debug("font registration failed for \(file.lastPathComponent): \(String(describing: error))")
                }
            }
        }

        if NSFont(name: regularName, size: 12) == nil {
            Log.debug("Silkscreen not available, falling back to system mono")
        }
    }

    static func regular(_ size: CGFloat) -> NSFont {
        font(named: regularName, size: size, weight: .regular)
    }

    static func bold(_ size: CGFloat) -> NSFont {
        font(named: boldName, size: size, weight: .bold)
    }

    private static func font(named name: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let key = "\(name)-\(size)"
        if let cached = cache[key] { return cached }
        let font = NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        cache[key] = font
        return font
    }
}
