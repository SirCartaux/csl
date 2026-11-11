import AppKit

/// Sits above the panel and paints the warm halo around it. Its own layer
/// opacity uses one finite Core Animation entrance; the resting halo is static. The panel interior is clipped out, everything the user
/// can click lives below this view (`hitTest` returns nil).
final class GlowView: NSView {
    /// Lets the launcher and the settings window share the same halo code.
    var panelRectProvider: (CGRect) -> CGRect = { Layout.panelRect(in: $0) }
    var ledRectProvider: ((CGRect) -> CGRect?)? = { panel in
        CGRect(x: panel.minX + 18, y: panel.minY + 14, width: 4, height: 4)
    }

    /// 1 for the Settings window, `Theme.launcherScale` for the launcher.
    var scale: CGFloat = 1

    private let rings: [(CGFloat, CGFloat)] = [(1, 0.12), (3, 0.035)]

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
        layer.opacity = 0.65
        guard InteractionMotion.enabled else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.95
        animation.toValue = 0.65
        animation.duration = 0.7
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "pulse")
        Log.debug("glow pulse started: \(layer.animationKeys() ?? [])")
    }

    func stopPulse() {
        layer?.removeAnimation(forKey: "pulse")
        layer?.opacity = 0.65
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let panel = panelRectProvider(bounds)

        // A restrained rim, with no opaque amber fill outside the surface.
        // Stroke-only bloom stays subtle in both native and bitmap rendering.
        context.saveGState()
        context.setShadow(offset: .zero, blur: 14 * scale,
                          color: Theme.accent.withAlphaComponent(0.10).cgColor)
        context.setStrokeColor(Theme.accent.withAlphaComponent(0.14).cgColor)
        context.setLineWidth(max(0.5, scale))
        context.addPath(CGPath(roundedRect: panel.insetBy(dx: -scale, dy: -scale),
                              cornerWidth: 9 * scale, cornerHeight: 9 * scale, transform: nil))
        context.strokePath()
        context.restoreGState()
        for (distance, alpha) in rings {
            let rim = NSBezierPath(roundedRect: panel.insetBy(dx: -distance * scale, dy: -distance * scale),
                                   xRadius: 9 * scale, yRadius: 9 * scale)
            rim.lineWidth = max(0.5, scale)
            Theme.accent.withAlphaComponent(alpha).setStroke()
            rim.stroke()
        }

        // Static bloom around the little status LED, if this window has one.
        if let led = ledRectProvider?(panel) {
            PixelDraw.fill(led.insetBy(dx: -5 * scale, dy: -5 * scale), Theme.accent.withAlphaComponent(0.03))
            PixelDraw.fill(led.insetBy(dx: -3 * scale, dy: -3 * scale), Theme.accent.withAlphaComponent(0.06))
            PixelDraw.fill(led.insetBy(dx: -1 * scale, dy: -1 * scale), Theme.accent.withAlphaComponent(0.12))
        }
    }
}
