import AppKit

/// Sits above the panel and paints the warm halo around it. Its own layer
/// opacity is animated with Core Animation, so the breathing glow costs
/// essentially no CPU. The panel interior is clipped out, everything the user
/// can click lives below this view (`hitTest` returns nil).
final class GlowView: NSView {
    /// Lets the launcher and the settings window share the same halo code.
    var panelRectProvider: (CGRect) -> CGRect = { Layout.panelRect(in: $0) }
    var ledRectProvider: ((CGRect) -> CGRect?)? = { panel in
        CGRect(x: panel.minX + 18, y: panel.minY + 14, width: 4, height: 4)
    }

    private let rings: [(CGFloat, CGFloat)] = [(1, 0.40), (2, 0.18), (4, 0.08), (7, 0.03)]

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.needsDisplayOnBoundsChange = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.needsDisplayOnBoundsChange = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func startPulse() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "pulse")
        layer.opacity = 1

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.58
        animation.duration = 1.75
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "pulse")
        Log.debug("glow pulse started: \(layer.animationKeys() ?? [])")
    }

    func stopPulse() {
        layer?.removeAnimation(forKey: "pulse")
        layer?.opacity = 1
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let panel = panelRectProvider(bounds)

        // Soft bloom, clipped to everything outside the panel.
        context.saveGState()
        context.addRect(bounds)
        context.addRect(panel)
        context.clip(using: .evenOdd)

        context.setFillColor(Theme.accent.cgColor)
        context.setShadow(
            offset: .zero,
            blur: 26,
            color: Theme.accent.withAlphaComponent(0.34).cgColor
        )
        context.fill(panel)
        context.setShadow(
            offset: .zero,
            blur: 7,
            color: Theme.accent.withAlphaComponent(0.50).cgColor
        )
        context.fill(panel)
        context.restoreGState()

        // Crisp pixel rings so the glow still reads as 8-bit art.
        for (distance, alpha) in rings {
            PixelDraw.frame(
                panel.insetBy(dx: -distance, dy: -distance),
                thickness: 1,
                color: Theme.accent.withAlphaComponent(alpha),
                notch: 2
            )
        }

        // Warm rim just inside the panel border.
        PixelDraw.frame(
            panel.insetBy(dx: 1, dy: 1),
            thickness: 1,
            color: Theme.accent.withAlphaComponent(0.11),
            notch: 2
        )

        // Pulsing bloom around the little status LED, if this window has one.
        if let led = ledRectProvider?(panel) {
            PixelDraw.fill(led.insetBy(dx: -5, dy: -5), Theme.accent.withAlphaComponent(0.03))
            PixelDraw.fill(led.insetBy(dx: -3, dy: -3), Theme.accent.withAlphaComponent(0.06))
            PixelDraw.fill(led.insetBy(dx: -1, dy: -1), Theme.accent.withAlphaComponent(0.12))
        }
    }
}
