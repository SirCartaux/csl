import AppKit
import QuartzCore

/// Three thin rectangular echoes that expand outward from a launching row.
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
            pulse.strokeColor = Theme.success.withAlphaComponent(index == 0 ? 0.9 : 0.68).cgColor
            pulse.lineWidth = max(1, Theme.ls(index == 0 ? 1.4 : 0.9))
            pulse.lineJoin = .miter
            pulse.lineCap = .butt
            pulse.shadowColor = Theme.success.cgColor
            pulse.shadowOffset = .zero
            pulse.shadowOpacity = index == 0 ? 0.8 : 0.5
            pulse.shadowRadius = Theme.ls(index == 0 ? 6 : 4)
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
        let path = CGPath(rect: rect, transform: nil)
        for pulse in pulses {
            pulse.bounds = CGRect(origin: .zero, size: bounds.size)
            pulse.position = CGPoint(x: bounds.midX, y: bounds.midY)
            pulse.path = path
        }
    }

    func start() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        let now = CACurrentMediaTime()
        for (index, pulse) in pulses.enumerated() {
            pulse.removeAllAnimations()
            pulse.opacity = 0
            let begin = now + Double(index) * 0.10
            let duration = 0.72

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1.0, 1.0, 1.035 + Double(index) * 0.025]
            scale.keyTimes = [0, 0.18, 1]
            scale.duration = duration
            scale.beginTime = begin
            scale.fillMode = .backwards
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.add(scale, forKey: "launchPulseScale")

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, index == 0 ? 0.90 : 0.68, 0.0]
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
