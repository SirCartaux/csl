import AppKit
import QuartzCore

/// A finite confirmation when a prefix becomes a command. Layers are reused;
/// neither typing its argument nor laying out the window restarts the effect.
final class CommandRecognitionView: NSView {
    private let badge = CALayer()
    private let fieldClip = CALayer()
    private let wash = CAGradientLayer()
    private let sweep = CAGradientLayer()
    private(set) var recognizedID: String?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        fieldClip.masksToBounds = true
        wash.startPoint = CGPoint(x: 0, y: 0.5)
        wash.endPoint = CGPoint(x: 1, y: 0.5)
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        fieldClip.addSublayer(wash)
        fieldClip.addSublayer(sweep)
        layer?.addSublayer(fieldClip)
        badge.shadowOffset = .zero
        badge.borderWidth = 1
        layer?.addSublayer(badge)
        stop()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    func update(command: InlineCommand?, prefixRect: CGRect, fieldRect: CGRect, animated: Bool) {
        guard let command else { stop(); return }
        let changed = recognizedID != command.recognitionID
        recognizedID = command.recognitionID
        guard !prefixRect.isNull, prefixRect.width > 1, fieldRect.width > 1 else {
            clearAnimations()
            return
        }
        let tint = command.tint
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badge.frame = prefixRect.insetBy(dx: -Theme.ls(4), dy: -Theme.ls(2))
        badge.cornerRadius = Theme.ls(5)
        badge.borderColor = tint.withAlphaComponent(0.8).cgColor
        badge.backgroundColor = tint.withAlphaComponent(0.035).cgColor
        badge.shadowColor = tint.cgColor
        badge.shadowOpacity = 0.3
        badge.shadowRadius = Theme.ls(7)
        badge.shadowPath = CGPath(roundedRect: badge.bounds, cornerWidth: badge.cornerRadius,
                                  cornerHeight: badge.cornerRadius, transform: nil)
        fieldClip.frame = fieldRect.insetBy(dx: Theme.ls(12), dy: Theme.ls(1))
        fieldClip.cornerRadius = Theme.ls(6)
        wash.frame = fieldClip.bounds
        wash.colors = [tint.withAlphaComponent(0.11).cgColor, tint.withAlphaComponent(0.025).cgColor, NSColor.clear.cgColor]
        sweep.bounds = CGRect(x: 0, y: 0, width: min(Theme.ls(160), fieldClip.bounds.width * 0.3), height: Theme.ls(1.5))
        sweep.position = CGPoint(x: 0, y: fieldClip.bounds.maxY - Theme.ls(1))
        sweep.colors = [NSColor.clear.cgColor, tint.withAlphaComponent(0.8).cgColor, NSColor.clear.cgColor]
        CATransaction.commit()
        guard animated, InteractionMotion.enabled else { clearAnimations(); return }
        guard changed else { return }
        clearAnimations()

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.94, 1.035, 1]
        scale.keyTimes = [0, 0.32, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.85, 0.36, 0]
        fade.keyTimes = [0, 0.16, 0.6, 1]
        let confirmation = CAAnimationGroup()
        confirmation.animations = [scale, fade]
        confirmation.duration = 0.56
        confirmation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        confirmation.beginTime = badge.convertTime(CACurrentMediaTime(), from: nil)
        badge.add(confirmation, forKey: "commandRecognized")

        let washFade = CAKeyframeAnimation(keyPath: "opacity")
        washFade.values = [0, 0.7, 0]
        washFade.keyTimes = [0, 0.22, 1]
        washFade.duration = 0.48
        wash.add(washFade, forKey: "commandWash")

        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = -sweep.bounds.width / 2
        travel.toValue = fieldClip.bounds.width + sweep.bounds.width / 2
        let light = CAKeyframeAnimation(keyPath: "opacity")
        light.values = [0, 0.9, 0]
        light.keyTimes = [0, 0.3, 1]
        let shimmer = CAAnimationGroup()
        shimmer.animations = [travel, light]
        shimmer.duration = 0.62
        shimmer.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sweep.add(shimmer, forKey: "commandSweep")
    }

    private func clearAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in [badge, wash, sweep] {
            item.removeAllAnimations()
            item.opacity = 0
        }
        CATransaction.commit()
    }

    func stop() {
        recognizedID = nil
        clearAnimations()
    }
}
