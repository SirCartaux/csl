import AppKit
import QuartzCore

/// A shared motion language. All animation is compositor-driven; no idle timer.
enum InteractionMotion {
    private static let disabled = ProcessInfo.processInfo.environment["CSL_NO_PIXEL_ANIMATION"] == "1"
    static var enabled: Bool {
        !disabled && SettingsStore.shared.motionPreference.allowsAnimation(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static func transition(_ changes: () -> Void, duration: TimeInterval = 0.18) {
        CATransaction.begin()
        CATransaction.setDisableActions(!enabled)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
        changes()
        CATransaction.commit()
    }

    static func appear(on layer: CALayer, duration: TimeInterval) {
        guard enabled else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.972; scale.toValue = 1
        let lift = CABasicAnimation(keyPath: "transform.translation.y")
        lift.fromValue = 8; lift.toValue = 0
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0; opacity.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [scale, lift, opacity]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.22, 1)
        layer.add(group, forKey: "launcherAppear")
    }

    static func disappear(on layer: CALayer, duration: TimeInterval) {
        guard enabled else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        scale.toValue = 0.985
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = layer.presentation()?.opacity ?? 1; opacity.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeIn)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "launcherDisappear")
    }
}

/// Pass-through optical feedback, clipped to the launcher. The fixed layer pool
/// is reused for every pointer/key/click event, never creating an animation loop.
final class InteractionEffectsView: NSView {
    private let surface = CALayer()
    private let pointerLight = CAGradientLayer()
    private let topLight = CAGradientLayer()
    private let inputLight = CAGradientLayer()
    private let listSurface = CALayer()
    private let hoverLight = CAGradientLayer()
    private let selectionLight = CAGradientLayer()
    private var ripples: [CALayer] = []
    private var rippleIndex = 0
    private var tracking: NSTrackingArea?
    private var lastPointerTime: TimeInterval = 0
    private var lastPulseTime: TimeInterval = 0
    private var listOrigin = CGPoint.zero
    private var hoverFrame: CGRect?
    private var selectionFrame: CGRect?
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
        configureRadial(pointerLight, alpha: 0.11)
        configureRadial(topLight, alpha: 0.13)
        pointerLight.opacity = 0
        surface.addSublayer(topLight)
        surface.addSublayer(pointerLight)
        listSurface.masksToBounds = true
        surface.addSublayer(listSurface)
        for (light, alpha) in [(selectionLight, CGFloat(0.12)), (hoverLight, CGFloat(0.075))] {
            light.colors = [Theme.accent.withAlphaComponent(alpha).cgColor, Theme.accent.withAlphaComponent(alpha*0.2).cgColor, NSColor.clear.cgColor]
            light.startPoint = CGPoint(x:0,y:0.5); light.endPoint = CGPoint(x:1,y:0.5)
            light.cornerRadius = 3
            light.borderWidth = 0.5
            light.borderColor = Theme.accent.withAlphaComponent(alpha*2).cgColor
            light.opacity = 0
            listSurface.addSublayer(light)
        }
        inputLight.colors = [NSColor.clear.cgColor, Theme.accent.cgColor, Theme.text.cgColor, Theme.accent.cgColor, NSColor.clear.cgColor]
        inputLight.locations = [0,0.3,0.5,0.7,1]
        inputLight.startPoint = CGPoint(x:0,y:0.5); inputLight.endPoint = CGPoint(x:1,y:0.5)
        inputLight.opacity = 0
        surface.addSublayer(inputLight)
        for _ in 0..<4 {
            let ripple = CALayer()
            ripple.bounds = CGRect(x:0,y:0,width:40,height:40)
            ripple.cornerRadius = 20
            ripple.borderWidth = 1
            ripple.borderColor = Theme.accent.withAlphaComponent(0.65).cgColor
            ripple.backgroundColor = Theme.accent.withAlphaComponent(0.025).cgColor
            ripple.opacity = 0
            surface.addSublayer(ripple)
            ripples.append(ripple)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureRadial(_ gradient: CAGradientLayer, alpha: CGFloat) {
        gradient.type = .radial
        gradient.colors = [Theme.accent.withAlphaComponent(alpha).cgColor, Theme.accent.withAlphaComponent(alpha*0.3).cgColor, NSColor.clear.cgColor]
        gradient.locations = [0,0.35,1]
        gradient.startPoint = CGPoint(x:0.5,y:0.5); gradient.endPoint = CGPoint(x:1,y:1)
    }

    override func layout() {
        super.layout()
        let panel = Layout.panelRect(in: bounds)
        let list = Layout.listRect(in: bounds)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        surface.frame = panel
        pointerLight.bounds = CGRect(x:0,y:0,width:Theme.ls(260),height:Theme.ls(190))
        topLight.frame = CGRect(x:panel.width*0.08,y:-Theme.ls(80),width:panel.width*0.84,height:Theme.ls(165))
        listOrigin = list.origin
        listSurface.frame = list.offsetBy(dx:-panel.minX,dy:-panel.minY)
        inputLight.frame = CGRect(x:Theme.ls(20),y:Theme.headerHeight+Theme.fieldHeight-Theme.ls(1.5),width:panel.width-Theme.ls(40),height:Theme.ls(1.5))
        if let selectionFrame { selectionLight.frame = localList(selectionFrame) }
        if let hoverFrame { hoverLight.frame = localList(hoverFrame) }
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect], owner:self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) { pointerMoved(to:convert(event.locationInWindow,from:nil)) }
    override func mouseExited(with event: NSEvent) {
        InteractionMotion.transition { self.pointerLight.opacity = 0; self.hoverLight.opacity = 0 }
        hoverFrame = nil
        onPointerMove?(nil)
    }

    func activate() {
        active = true
        window?.acceptsMouseMovedEvents = true
        needsLayout = true
    }
    func stop() {
        active = false
        hoverFrame = nil; selectionFrame = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for light in [pointerLight, inputLight, hoverLight, selectionLight] { light.removeAllAnimations(); light.opacity = 0 }
        for ripple in ripples { ripple.removeAllAnimations(); ripple.opacity = 0 }
        CATransaction.commit()
    }

    func pointerMoved(to point: CGPoint) {
        guard active else { return }
        let now = CACurrentMediaTime()
        // Bound hover work on very high polling-rate mice; CA interpolates motion.
        guard now-lastPointerTime >= 1.0/120 else { return }
        lastPointerTime = now
        let panel = Layout.panelRect(in: bounds)
        guard panel.contains(point) else {
            InteractionMotion.transition { self.pointerLight.opacity = 0 }
            setHover(nil); return
        }
        InteractionMotion.transition({
            self.pointerLight.position = CGPoint(x:point.x-panel.minX,y:point.y-panel.minY)
            self.pointerLight.opacity = 1
        }, duration:0.12)
        onPointerMove?(point)
    }

    private func localList(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx:-listOrigin.x,dy:-listOrigin.y).insetBy(dx:Theme.ls(1),dy:0.5)
    }
    func setHover(_ rect: CGRect?) {
        guard hoverFrame != rect else { return }
        let wasVisible = hoverFrame != nil
        hoverFrame = rect
        guard active else { return }
        if let rect, !wasVisible {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            hoverLight.frame = localList(rect)
            CATransaction.commit()
        }
        InteractionMotion.transition {
            if let rect { self.hoverLight.frame = self.localList(rect) }
            self.hoverLight.opacity = rect == nil ? 0 : 1
        }
    }
    func setSelection(_ rect: CGRect?, animated: Bool) {
        let previous = selectionFrame
        selectionFrame = rect
        guard active else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || previous == nil || !InteractionMotion.enabled)
        CATransaction.setAnimationDuration(0.16)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints:0.18,0.85,0.25,1))
        if let rect { selectionLight.frame = localList(rect) }
        selectionLight.opacity = rect == nil ? 0 : 1
        CATransaction.commit()
    }

    func inputPulse(success: Bool = false) {
        guard active, InteractionMotion.enabled else { return }
        let now = CACurrentMediaTime()
        guard success || now-lastPulseTime > 0.045 else { return }
        lastPulseTime = now
        let opacity = CAKeyframeAnimation(keyPath:"opacity")
        opacity.values = [inputLight.presentation()?.opacity ?? 0, success ? 1 : 0.65, 0]
        opacity.keyTimes = [0,0.18,1]; opacity.duration = success ? 0.6 : 0.38
        let width = CABasicAnimation(keyPath:"transform.scale.x")
        width.fromValue = 0.75; width.toValue = 1; width.duration = 0.38
        inputLight.add(opacity,forKey:"inputPulse")
        inputLight.add(width,forKey:"inputExpand")
    }

    func click(at point: CGPoint) {
        guard active, InteractionMotion.enabled, Layout.panelRect(in: bounds).contains(point) else { return }
        let panel = Layout.panelRect(in: bounds)
        let ripple = ripples[rippleIndex]; rippleIndex = (rippleIndex+1)%ripples.count
        CATransaction.begin(); CATransaction.setDisableActions(true)
        ripple.removeAllAnimations()
        ripple.position = CGPoint(x:point.x-panel.minX,y:point.y-panel.minY)
        CATransaction.commit()
        let size = CABasicAnimation(keyPath:"transform.scale")
        size.fromValue = 0.2; size.toValue = 1.7
        let opacity = CABasicAnimation(keyPath:"opacity")
        opacity.fromValue = 0.8; opacity.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [size,opacity]; group.duration = 0.42
        group.timingFunction = CAMediaTimingFunction(name:.easeOut)
        ripple.add(group,forKey:"clickImpulse")
    }
}
