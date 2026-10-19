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

        let glyph = PixelGlyph.clipboard.image(size: Theme.ls(11), color: color)
        glyph.draw(in: CGRect(
            x: Theme.ls(7),
            y: (bounds.height - Theme.ls(11)) / 2,
            width: Theme.ls(11),
            height: Theme.ls(11)
        ))

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        ("CLIP" as NSString).draw(
            in: CGRect(
                x: Theme.ls(22),
                y: (bounds.height - Theme.ls(10)) / 2 + Theme.ls(1),
                width: bounds.width - Theme.ls(27),
                height: Theme.ls(12)
            ),
            withAttributes: [
                .font: Theme.launcherDisplay(6.5),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}
