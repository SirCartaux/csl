import AppKit

/// Six tiny hand swatches: default plus the five Unicode skin tones.
/// The chosen tone is applied when an emoji is inserted; the database stores
/// the exact pre-composed sequence for each base emoji.
final class SkinToneView: NSView {
    var onSelect: ((Int) -> Void)?
    var tone: Int = 0 {
        didSet { needsDisplay = true }
    }

    private let swatches = ["✋", "✋🏻", "✋🏼", "✋🏽", "✋🏾", "✋🏿"]
    private var hovered: Int?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "SKIN TONE"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        tracking = area
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let index = swatch(at: convert(event.locationInWindow, from: nil))
        guard index != hovered else { return }
        hovered = index
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = swatch(at: convert(event.locationInWindow, from: nil)) else { return }
        tone = index
        onSelect?(index)
    }

    private func swatchRect(_ index: Int) -> CGRect {
        let size: CGFloat = 14
        let gap: CGFloat = 2
        let total = CGFloat(swatches.count) * size + CGFloat(swatches.count - 1) * gap
        let startX = floor((bounds.width - total) / 2)
        return CGRect(
            x: startX + CGFloat(index) * (size + gap),
            y: floor((bounds.height - size) / 2),
            width: size,
            height: size
        )
    }

    private func swatch(at point: CGPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        for index in swatches.indices where swatchRect(index).insetBy(dx: -1, dy: -1).contains(point) {
            return index
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont(name: "Apple Color Emoji", size: 10) ?? NSFont.systemFont(ofSize: 10)
        for index in swatches.indices {
            let rect = swatchRect(index)
            let isSelected = index == tone
            let isHovered = index == hovered
            if isSelected {
                PixelDraw.fill(rect.insetBy(dx: -1, dy: -1), Theme.bgSelected)
                PixelDraw.frame(rect.insetBy(dx: -1, dy: -1), thickness: 1, color: Theme.accent, notch: 2)
            } else if isHovered {
                PixelDraw.frame(rect.insetBy(dx: -1, dy: -1), thickness: 1, color: Theme.borderBright, notch: 2)
            }

            let text = swatches[index] as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                in: CGRect(
                    x: rect.midX - size.width / 2,
                    y: rect.midY - size.height / 2,
                    width: size.width + 2,
                    height: size.height
                ),
                withAttributes: attributes
            )
        }
    }
}
