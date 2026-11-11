import AppKit
import QuartzCore

/// Three restrained, softly rounded echoes that expand outward from a launching row.
/// This lives above the list (not inside the row) so the top and bottom edges
/// are not clipped by the table cell.
final class LaunchPulseView: NSView {
    private var pulses: [CAShapeLayer] = []

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for index in 0..<3 {
            let pulse = CAShapeLayer()
            pulse.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            pulse.fillColor = nil
            pulse.strokeColor = Theme.success.withAlphaComponent(index == 0 ? 0.55 : 0.3).cgColor
            pulse.lineWidth = max(1, Theme.ls(index == 0 ? 1.4 : 0.9))
            pulse.lineJoin = .round
            pulse.lineCap = .butt
            pulse.shadowColor = Theme.success.cgColor
            pulse.shadowOffset = .zero
            pulse.shadowOpacity = index == 0 ? 0.3 : 0.15
            pulse.shadowRadius = Theme.ls(index == 0 ? 4 : 2)
            pulse.opacity = 0
            layer?.addSublayer(pulse)
            pulses.append(pulse)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: Theme.ls(2), dy: Theme.ls(2))
        let path = CGPath(roundedRect: rect, cornerWidth: Theme.ls(6), cornerHeight: Theme.ls(6), transform: nil)
        for pulse in pulses {
            pulse.bounds = CGRect(origin: .zero, size: bounds.size)
            pulse.position = CGPoint(x: bounds.midX, y: bounds.midY)
            pulse.path = path
        }
    }

    func start() {
        stop()
        guard InteractionMotion.enabled else { return }
        needsLayout = true
        layoutSubtreeIfNeeded()
        let now = CACurrentMediaTime()
        for (index, pulse) in pulses.enumerated() {
            pulse.removeAllAnimations()
            pulse.opacity = 0
            let begin = now + Double(index) * 0.08
            let duration = 0.55

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1.0, 1.0, 1.02 + Double(index) * 0.015]
            scale.keyTimes = [0, 0.18, 1]
            scale.duration = duration
            scale.beginTime = begin
            scale.fillMode = .backwards
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.add(scale, forKey: "launchPulseScale")

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, index == 0 ? 0.55 : 0.3, 0.0]
            fade.keyTimes = [0, 0.22, 1]
            fade.duration = duration
            fade.beginTime = begin
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.add(fade, forKey: "launchPulseFade")
        }
    }

    func stop() {
        for pulse in pulses {
            pulse.removeAllAnimations()
            pulse.opacity = 0
        }
    }
}
