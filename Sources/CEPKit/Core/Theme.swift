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
///
/// The palette is deliberately shared verbatim with CSL: warm cream on
/// near-black with a single amber accent, hard edges, no blur and no rounded
/// corners. CEP is meant to read as a sibling of the launcher.
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
    static let success = NSColor(hex: 0x74E08A)

    // Panel geometry. The glow lives in the 32 pt transparent inset around
    // the panel; everything visible is drawn inside `panelWidth` × `panelHeight`.
    static let panelInset: CGFloat = 32
    static let panelWidth: CGFloat = 660
    static let panelHeight: CGFloat = 400

    static var windowWidth: CGFloat { panelWidth + 2 * panelInset }
    static var windowHeight: CGFloat { panelHeight + 2 * panelInset }

    static let headerHeight: CGFloat = 32
    static let fieldHeight: CGFloat = 52
    static let footerHeight: CGFloat = 28
    static var bodyHeight: CGFloat { panelHeight - headerHeight - fieldHeight - footerHeight }

    static let sidebarWidth: CGFloat = 112
    static let sidebarRowHeight: CGFloat = 22
    static let sidebarPadding: CGFloat = 12

    static let gridHeaderHeight: CGFloat = 26
    static let gridPadding: CGFloat = 22
    static let gridVerticalPadding: CGFloat = 5
    static let cellWidth: CGFloat = 42
    static let cellHeight: CGFloat = 42
    static let gridColumns: CGFloat = 12

    // Drawing helpers
    static func display(_ size: CGFloat) -> NSFont { PixelFont.regular(size) }
    static func displayBold(_ size: CGFloat) -> NSFont { PixelFont.bold(size) }

    static let emojiFont = NSFont(name: "Apple Color Emoji", size: 27)
        ?? NSFont.systemFont(ofSize: 27)
    static let symbolFont = NSFont(name: "Apple Symbols", size: 21) ?? NSFont.systemFont(ofSize: 21, weight: .regular)
    static let kaomojiFont = NSFont(name: "Menlo", size: 12)
        ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let sidebarEmojiFont = NSFont(name: "Apple Color Emoji", size: 12)
        ?? NSFont.systemFont(ofSize: 12)
}
