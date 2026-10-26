import AppKit
import QuartzCore

/// A shared motion language. All animation is compositor-driven; no idle timer.
enum InteractionMotion {
    private static let disabled = ProcessInfo.processInfo.environment["CEP_NO_ANIMATION"] == "1"
    static var enabled: Bool {
        !disabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func transition(_ changes: () -> Void, duration: TimeInterval = 0.16) {
        CATransaction.begin()
        CATransaction.setDisableActions(!enabled)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        )
        changes()
        CATransaction.commit()
    }

    static func appear(on layer: CALayer, duration: TimeInterval) {
        guard enabled else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.982
        scale.toValue = 1
        let lift = CABasicAnimation(keyPath: "transform.translation.y")
        lift.fromValue = 4
        lift.toValue = 0
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [scale, lift, opacity]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.22, 1)
        layer.add(group, forKey: "pickerAppear")
    }

    static func disappear(on layer: CALayer, duration: TimeInterval) {
        guard enabled else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        scale.toValue = 0.992
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = layer.presentation()?.opacity ?? 1
        opacity.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "pickerDisappear")
    }
}

/// Pass-through optical feedback, clipped to the panel. The fixed layer pool is
/// reused for pointer movement, typing and clicks, never creating an animation
/// loop or an idle timer.
final class InteractionEffectsView: NSView {
    private let surface = CALayer()
    private let pointerLight = CAGradientLayer()
    private let topLight = CAGradientLayer()
    private let inputLight = CAGradientLayer()
    private var ripples: [CALayer] = []
    private var rippleIndex = 0
    private var tracking: NSTrackingArea?
    private var lastPointerTime: TimeInterval = 0
    private var lastPulseTime: TimeInterval = 0
    var onPointerMove: ((CGPoint?) -> Void)?
    private(set) var active = false

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(surface)
        surface.masksToBounds = true
        surface.cornerRadius = 3

        configureRadial(pointerLight, alpha: 0.10)
        configureRadial(topLight, alpha: 0.13)
        pointerLight.opacity = 0
        surface.addSublayer(topLight)
        surface.addSublayer(pointerLight)

        inputLight.colors = [
            NSColor.clear.cgColor,
            Theme.accent.cgColor,
            Theme.text.cgColor,
            Theme.accent.cgColor,
            NSColor.clear.cgColor
        ]
        inputLight.locations = [0, 0.3, 0.5, 0.7, 1]
        inputLight.startPoint = CGPoint(x: 0, y: 0.5)
        inputLight.endPoint = CGPoint(x: 1, y: 0.5)
        inputLight.opacity = 0
        surface.addSublayer(inputLight)

        for _ in 0..<4 {
            let ripple = CALayer()
            ripple.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
            ripple.cornerRadius = 20
            ripple.borderWidth = 1
            ripple.borderColor = Theme.accent.withAlphaComponent(0.65).cgColor
            ripple.backgroundColor = Theme.accent.withAlphaComponent(0.025).cgColor
            ripple.opacity = 0
            surface.addSublayer(ripple)
            ripples.append(ripple)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureRadial(_ gradient: CAGradientLayer, alpha: CGFloat) {
        gradient.type = .radial
        gradient.colors = [
            Theme.accent.withAlphaComponent(alpha).cgColor,
            Theme.accent.withAlphaComponent(alpha * 0.3).cgColor,
            NSColor.clear.cgColor
        ]
        gradient.locations = [0, 0.35, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 1)
    }

    override func layout() {
        super.layout()
        let panel = Layout.panelRect(in: bounds)
        let field = Layout.fieldRect(in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.frame = panel
        pointerLight.bounds = CGRect(x: 0, y: 0, width: 260, height: 190)
        topLight.frame = CGRect(
            x: panel.width * 0.08,
            y: -80,
            width: panel.width * 0.84,
            height: 165
        )
        inputLight.frame = CGRect(
            x: 20,
            y: field.maxY - panel.minY - 1.5,
            width: panel.width - 40,
            height: 1.5
        )
        CATransaction.commit()
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
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        InteractionMotion.transition { self.pointerLight.opacity = 0 }
        onPointerMove?(nil)
    }

    func activate() {
        active = true
        window?.acceptsMouseMovedEvents = true
        needsLayout = true
    }

    func stop() {
        active = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [pointerLight, inputLight] {
            layer.removeAllAnimations()
            layer.opacity = 0
        }
        for ripple in ripples {
            ripple.removeAllAnimations()
            ripple.opacity = 0
        }
        CATransaction.commit()
    }

    func pointerMoved(to point: CGPoint) {
        guard active else { return }
        let now = CACurrentMediaTime()
        guard now - lastPointerTime >= 1.0 / 120 else { return }
        lastPointerTime = now
        let panel = Layout.panelRect(in: bounds)
        guard panel.contains(point) else {
            InteractionMotion.transition { self.pointerLight.opacity = 0 }
            return
        }
        InteractionMotion.transition({
            self.pointerLight.position = CGPoint(x: point.x - panel.minX, y: point.y - panel.minY)
            self.pointerLight.opacity = 1
        }, duration: 0.12)
        onPointerMove?(point)
    }

    func inputPulse(success: Bool = false) {
        guard active, InteractionMotion.enabled else { return }
        let now = CACurrentMediaTime()
        guard success || now - lastPulseTime > 0.045 else { return }
        lastPulseTime = now
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [inputLight.presentation()?.opacity ?? 0, success ? 1 : 0.65, 0]
        opacity.keyTimes = [0, 0.18, 1]
        opacity.duration = success ? 0.6 : 0.38
        let width = CABasicAnimation(keyPath: "transform.scale.x")
        width.fromValue = 0.75
        width.toValue = 1
        width.duration = 0.38
        inputLight.add(opacity, forKey: "inputPulse")
        inputLight.add(width, forKey: "inputExpand")
    }

    func click(at point: CGPoint) {
        guard active, InteractionMotion.enabled, Layout.panelRect(in: bounds).contains(point) else { return }
        let panel = Layout.panelRect(in: bounds)
        let ripple = ripples[rippleIndex]
        rippleIndex = (rippleIndex + 1) % ripples.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ripple.removeAllAnimations()
        ripple.position = CGPoint(x: point.x - panel.minX, y: point.y - panel.minY)
        CATransaction.commit()
        let size = CABasicAnimation(keyPath: "transform.scale")
        size.fromValue = 0.2
        size.toValue = 1.7
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.8
        opacity.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [size, opacity]
        group.duration = 0.42
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "clickImpulse")
    }
}
