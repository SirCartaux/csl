import AppKit

/// The inline `= result` badge that sits after the typed calculation.
final class CalculatorHintView: NSView {
    var resultText = "" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func badgeSize(for result: String) -> NSSize {
        let size = attributed(result).size()
        return NSSize(
            width: ceil(size.width) + Theme.ls(16),
            height: max(Theme.ls(22), ceil(size.height) + Theme.ls(8))
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.fill(bounds, Theme.accent.withAlphaComponent(0.10))
        PixelDraw.frame(
            bounds.insetBy(dx: 0.5, dy: 0.5),
            thickness: max(1, Theme.ls(1)),
            color: Theme.accent.withAlphaComponent(0.55),
            notch: Theme.ls(2)
        )

        let text = attributed(resultText)
        let size = text.size()
        text.draw(at: NSPoint(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2)
        ))
    }

    private func attributed(_ result: String) -> NSAttributedString {
        let font = Theme.launcherDisplay(12.5)
        let string = NSMutableAttributedString()
        string.append(NSAttributedString(
            string: "= ",
            attributes: [.font: font, .foregroundColor: Theme.accent]
        ))
        string.append(NSAttributedString(
            string: result,
            attributes: [.font: font, .foregroundColor: Theme.success]
        ))
        return string
    }
}
