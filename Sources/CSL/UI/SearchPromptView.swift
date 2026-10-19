import AppKit
import QuartzCore

/// The amber `>` at the start of the query. It gives a tiny pop and glow on
/// every text edit, without leaving an animation running afterwards.
final class SearchPromptView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = Theme.accent.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 0
        layer?.shadowRadius = Theme.ls(3)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.chevron(
            x: Theme.ls(4),
            y: Theme.ls(4),
            unit: Theme.ls(3),
            color: Theme.accent
        )
    }

    func pulse() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "promptScale")
        layer.removeAnimation(forKey: "promptGlow")
        layer.removeAnimation(forKey: "promptGlowRadius")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 1.18, 1.0]
        scale.keyTimes = [0, 0.32, 1]
        scale.duration = 0.22
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scale, forKey: "promptScale")

        let glow = CAKeyframeAnimation(keyPath: "shadowOpacity")
        glow.values = [0.15, 1.0, 0.2]
        glow.keyTimes = [0, 0.35, 1]
        glow.duration = 0.36
        glow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(glow, forKey: "promptGlow")

        let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
        radius.values = [Theme.ls(2), Theme.ls(7), Theme.ls(3)]
        radius.keyTimes = [0, 0.35, 1]
        radius.duration = 0.36
        radius.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(radius, forKey: "promptGlowRadius")
    }

    func stop() {
        layer?.removeAllAnimations()
        layer?.shadowOpacity = 0
    }
}
