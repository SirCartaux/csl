import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// All colours, fonts and metrics in one place.
/// Palette: warm cream on near-black, one amber accent. No rounded corners, no blur.
enum Theme {
    // Surfaces
    static let bg = NSColor(hex: 0x0E0E16)
    static let bgRaised = NSColor(hex: 0x13131E)
    static let bgSelected = NSColor(hex: 0x1D1D2C)
    static let shadow = NSColor.black.withAlphaComponent(0.45)

    // Lines
    static let line = NSColor(hex: 0x24243A)
    static let border = NSColor(hex: 0x3B3B55)
    static let borderBright = NSColor(hex: 0x62628A)

    // Type
    static let text = NSColor(hex: 0xEDE6D6)
    static let textDim = NSColor(hex: 0x9A9AB4)
    static let textFaint = NSColor(hex: 0x5E5E7A)
    static let accent = NSColor(hex: 0xFFC24B)
    static let accentDim = NSColor(hex: 0x9C7429)
    static let danger = NSColor(hex: 0xFF6B6B)

    // Launcher metrics. `launcherScale` is driven by the resize handles;
    // everything visible in the launcher (layout, fonts, borders) multiplies
    // through this value, while the Settings window keeps its own fixed size.
    static let minLauncherScale: CGFloat = 0.7
    static let maxLauncherScale: CGFloat = 2.2
    static var launcherScale: CGFloat = 1

    static func ls(_ value: CGFloat) -> CGFloat { value * launcherScale }

    static var panelInset: CGFloat { ls(32) }
    static var panelWidth: CGFloat { ls(700) }
    static var headerHeight: CGFloat { ls(32) }
    static var fieldHeight: CGFloat { ls(54) }
    static var rowHeight: CGFloat { ls(42) }
    static var footerHeight: CGFloat { ls(28) }
    static var emptyListHeight: CGFloat { ls(66) }
    static let maxRows = 7

    // Settings window
    static let settingsInset: CGFloat = 32
    static let settingsWidth: CGFloat = 780
    static let settingsHeight: CGFloat = 600
    static let settingsHeaderHeight: CGFloat = 48
    static let settingsSidebarWidth: CGFloat = 200

    static func display(_ size: CGFloat) -> NSFont { PixelFont.regular(size) }
    static func displayBold(_ size: CGFloat) -> NSFont { PixelFont.bold(size) }

    static func launcherDisplay(_ size: CGFloat) -> NSFont {
        PixelFont.regular(size * launcherScale)
    }

    static func launcherDisplayBold(_ size: CGFloat) -> NSFont {
        PixelFont.bold(size * launcherScale)
    }
}
