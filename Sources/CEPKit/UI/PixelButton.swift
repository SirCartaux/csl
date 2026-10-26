import AppKit

/// Small notched pixel button used by the setup window.
final class PixelButton: NSView {
    enum Style {
        case normal
        case accent
        case danger
    }

    var title: String {
        didSet { needsDisplay = true }
    }
    var style: Style {
        didSet { needsDisplay = true }
    }
    var isEnabled = true {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    init(title: String, style: Style = .normal) {
        self.title = title
        self.style = style
        super.init(frame: .zero)
        toolTip = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize {
        let width = (title as NSString).size(withAttributes: [.font: Theme.display(8.5)]).width
        return NSSize(width: ceil(width) + 20, height: 24)
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
        pressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if inside {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let accent = style == .accent ? Theme.accent : (style == .danger ? Theme.danger : Theme.borderBright)
        let border = isEnabled ? (hovered ? accent : Theme.border) : Theme.border.withAlphaComponent(0.5)
        let fill: NSColor
        if !isEnabled {
            fill = Theme.bgRaised.withAlphaComponent(0.4)
        } else if pressed {
            fill = Theme.bgSelected
        } else if hovered {
            fill = Theme.bgSelected
        } else {
            fill = Theme.bgRaised
        }

        PixelDraw.fill(rect, fill)
        PixelDraw.frame(rect, thickness: 1, color: border, notch: 2)

        if style == .accent, isEnabled {
            PixelDraw.fill(CGRect(x: rect.minX + 3, y: rect.minY, width: 2, height: 1), Theme.accent)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: isEnabled
                ? (style == .accent ? Theme.accent : (style == .danger ? Theme.danger : Theme.text))
                : Theme.textFaint
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(
            in: CGRect(
                x: floor(bounds.midX - size.width / 2),
                y: floor(bounds.midY - size.height / 2) + (pressed ? 1 : 0),
                width: size.width + 2,
                height: size.height
            ),
            withAttributes: attributes
        )
    }
}
