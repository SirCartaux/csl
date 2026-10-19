import AppKit

/// Small clipboard button in the launcher header, immediately left of the
/// CMD+SPACE cap.
final class ClipboardHeaderButton: NSView {
    var onToggle: (() -> Void)?
    var active = false {
        didSet { needsDisplay = true }
    }

    private var hovered = false
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Clipboard History (⌘⇧V)"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Clipboard History")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onToggle?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill = active
            ? Theme.accent.withAlphaComponent(0.14)
            : (hovered ? Theme.bgSelected : Theme.bgRaised)
        let border = active || hovered ? Theme.accent : Theme.border
        let color = active || hovered ? Theme.accent : Theme.textDim

        PixelDraw.fill(bounds, fill)
        PixelDraw.frame(bounds.insetBy(dx: 0.5, dy: 0.5), thickness: max(1, Theme.ls(1)), color: border, notch: Theme.ls(2))

        let label = "CLIP" as NSString
        let font = Theme.launcherDisplay(6.5)
        let textSize = label.size(withAttributes: [.font: font])
        let glyphSize = Theme.ls(11)
        let gap = Theme.ls(4)
        let groupWidth = glyphSize + gap + textSize.width
        let startX = floor((bounds.width - groupWidth) / 2)
        let glyphY = floor((bounds.height - glyphSize) / 2)

        let glyph = PixelGlyph.clipboard.image(size: glyphSize, color: color)
        glyph.draw(in: CGRect(x: startX, y: glyphY, width: glyphSize, height: glyphSize))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        label.draw(
            in: CGRect(
                x: startX + glyphSize + gap,
                y: floor((bounds.height - textSize.height) / 2),
                width: textSize.width + Theme.ls(1),
                height: textSize.height
            ),
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}
