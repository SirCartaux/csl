import AppKit

/// Small pixel “×” at the right end of the search field. Clicking clears the
/// query and keeps the picker open.
final class ClearButton: NSView {
    var onClick: (() -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "CLEAR SEARCH"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        tracking = area
        addTrackingArea(area)
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
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = hovered ? Theme.accent : Theme.textFaint
        let unit: CGFloat = 1
        let size: CGFloat = 7
        let origin = CGPoint(x: floor((bounds.width - size) / 2), y: floor((bounds.height - size) / 2))
        color.setFill()
        for index in 0..<Int(size) {
            CGRect(x: origin.x + CGFloat(index), y: origin.y + CGFloat(index), width: unit, height: unit).fill()
            CGRect(x: origin.x + size - 1 - CGFloat(index), y: origin.y + CGFloat(index), width: unit, height: unit).fill()
        }
    }
}
