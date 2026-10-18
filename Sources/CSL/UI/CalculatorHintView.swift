import AppKit

/// The inline `= result` badge that sits after the typed calculation.
final class CalculatorHintView: NSView {
    var resultText = "" {
        didSet { needsDisplay = true }
    }
    var onCopy: (() -> Void)?

    private var hovered = false {
        didSet { updateAppearance(); needsDisplay = true }
    }
    private var copied = false
    private var copyWork: DispatchWorkItem?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Click to copy"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Copy calculation result")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        copyWork?.cancel()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
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
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    override func mouseDown(with event: NSEvent) {
        onCopy?()
        flashCopied()
    }

    func badgeSize(for result: String) -> NSSize {
        let size = attributed(result).size()
        return NSSize(
            width: ceil(size.width) + Theme.ls(16),
            height: max(Theme.ls(22), ceil(size.height) + Theme.ls(8))
        )
    }

    func flashCopied() {
        copyWork?.cancel()
        copied = true
        updateAppearance()
        needsDisplay = true
        let work = DispatchWorkItem { [weak self] in
            self?.copied = false
            self?.updateAppearance()
            self?.needsDisplay = true
        }
        copyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private func updateAppearance() {
        layer?.shadowColor = (copied ? Theme.success : Theme.accent).cgColor
        layer?.shadowOpacity = copied ? 0.9 : (hovered ? 0.8 : 0.35)
        layer?.shadowRadius = copied ? Theme.ls(6) : (hovered ? Theme.ls(5) : Theme.ls(4))
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillColor: NSColor
        let borderColor: NSColor
        let equalsColor: NSColor
        let valueColor: NSColor

        if copied {
            fillColor = Theme.success.withAlphaComponent(0.18)
            borderColor = Theme.success.withAlphaComponent(0.90)
            equalsColor = Theme.success
            valueColor = Theme.success
        } else if hovered {
            fillColor = Theme.accent.withAlphaComponent(0.22)
            borderColor = Theme.accent.withAlphaComponent(0.95)
            equalsColor = Theme.text
            valueColor = Theme.success
        } else {
            fillColor = Theme.accent.withAlphaComponent(0.10)
            borderColor = Theme.accent.withAlphaComponent(0.55)
            equalsColor = Theme.accent
            valueColor = Theme.success
        }

        PixelDraw.fill(bounds, fillColor)
        PixelDraw.frame(
            bounds.insetBy(dx: 0.5, dy: 0.5),
            thickness: max(1, Theme.ls(1)),
            color: borderColor,
            notch: Theme.ls(2)
        )

        let text = attributed(resultText, equals: equalsColor, value: valueColor)
        let size = text.size()
        text.draw(at: NSPoint(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2)
        ))
    }

    private func attributed(_ result: String) -> NSAttributedString {
        attributed(result, equals: Theme.accent, value: Theme.success)
    }

    private func attributed(
        _ result: String,
        equals: NSColor,
        value: NSColor
    ) -> NSAttributedString {
        let font = Theme.launcherDisplay(12.5)
        let string = NSMutableAttributedString()
        string.append(NSAttributedString(
            string: "= ",
            attributes: [.font: font, .foregroundColor: equals]
        ))
        string.append(NSAttributedString(
            string: result,
            attributes: [.font: font, .foregroundColor: value]
        ))
        return string
    }
}
