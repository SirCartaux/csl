import AppKit
import QuartzCore

/// The amber `>` at the start of the query. The chevron lives in its own
/// centre-anchored sublayer so the pop scales around the glyph, never its
/// top-left corner, independent of AppKit's default view-layer anchor.
final class SearchPromptView: NSView {
    private let chevron = PromptChevronLayer()

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        chevron.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        chevron.shadowColor = Theme.accent.cgColor
        chevron.shadowOffset = .zero
        chevron.shadowOpacity = 0
        chevron.shadowRadius = Theme.ls(3)
        layer?.addSublayer(chevron)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let unit = Theme.ls(3)
        let size = CGSize(width: unit * 4, height: unit * 5)
        if chevron.bounds.size != size {
            chevron.bounds = CGRect(origin: .zero, size: size)
        }
        chevron.position = CGPoint(x: bounds.midX, y: bounds.midY)
        chevron.contentsScale = window?.backingScaleFactor ?? 2
        chevron.setNeedsDisplay()
    }

    func pulse() {
        chevron.removeAnimation(forKey: "promptScale")
        chevron.removeAnimation(forKey: "promptGlow")
        chevron.removeAnimation(forKey: "promptGlowRadius")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 1.18, 1.0]
        scale.keyTimes = [0, 0.32, 1]
        scale.duration = 0.22
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        chevron.add(scale, forKey: "promptScale")

        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [0.15, 1.0, 0.2]
        glow.keyTimes = [0, 0.35, 1]
        glow.duration = 0.36
        glow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        chevron.add(glow, forKey: "promptGlow")

        let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
        radius.values = [Theme.ls(2), Theme.ls(7), Theme.ls(3)]
        radius.keyTimes = [0, 0.35, 1]
        radius.duration = 0.36
        radius.timingFunction = CAMediaTimingFunction(name: .easeOut)
        chevron.add(radius, forKey: "promptGlowRadius")
    }

    func stop() {
        chevron.removeAllAnimations()
        chevron.shadowOpacity = 0
    }
}

private final class PromptChevronLayer: CALayer {
    override func draw(in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        PixelDraw.chevron(x: 0, y: 0, unit: Theme.ls(3), color: Theme.accent)
        NSGraphicsContext.restoreGraphicsState()
    }
}
