import AppKit
import QuartzCore

/// One result row: icon, title with match highlighting, dim path, selection bar.
/// While a launch is in flight the row turns green, presses in slightly and
/// emits a soft expanding outline.
final class ResultRowView: NSView {
    private var result: SearchResult?
    private var isSelected = false
    private var isLaunching = false
    private var pendingLaunchAnimation = false

    private let launchSpinner = LaunchSpinnerView(frame: .zero)
    private let launchWash = CALayer()
    private var launchPulses: [CAShapeLayer] = []

    var rowIndex: Int = 0
    var menuProvider: ((Int) -> NSMenu?)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        launchWash.backgroundColor = Theme.success.withAlphaComponent(0.10).cgColor
        launchWash.opacity = 0
        layer?.addSublayer(launchWash)

        // Three connected rectangular impulses: a slightly stronger first
        // outline and two thinner echoes, all expanding with ease-out.
        for index in 0..<3 {
            let pulse = CAShapeLayer()
            pulse.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            pulse.fillColor = nil
            pulse.strokeColor = Theme.success.withAlphaComponent(index == 0 ? 0.9 : 0.7).cgColor
            pulse.lineWidth = max(1, Theme.ls(index == 0 ? 1.4 : 0.9))
            pulse.lineJoin = .miter
            pulse.lineCap = .butt
            pulse.shadowColor = Theme.success.cgColor
            pulse.shadowOffset = .zero
            pulse.shadowOpacity = index == 0 ? 0.8 : 0.55
            pulse.shadowRadius = Theme.ls(index == 0 ? 6 : 4)
            pulse.opacity = 0
            layer?.addSublayer(pulse)
            launchPulses.append(pulse)
        }

        addSubview(launchSpinner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let size = Theme.ls(16)
        launchSpinner.frame = CGRect(
            x: bounds.width - Theme.ls(24) - size,
            y: floor((bounds.height - size) / 2),
            width: size,
            height: size
        )

        if pendingLaunchAnimation, bounds.width > 1 {
            pendingLaunchAnimation = false
            setLaunching(isLaunching, animated: true)
        }

        launchWash.frame = bounds
        for pulse in launchPulses {
            pulse.bounds = CGRect(origin: .zero, size: bounds.size)
            pulse.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        updateOutlinePaths()
    }

    func configure(with result: SearchResult, selected: Bool, launching: Bool = false) {
        self.result = result
        self.isSelected = selected
        if isLaunching != launching {
            isLaunching = launching
            if bounds.width > 1 {
                setLaunching(launching, animated: true)
            } else {
                pendingLaunchAnimation = true
            }
        }
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - Launch state

    private func setLaunching(_ launching: Bool, animated: Bool) {
        if launching {
            launchSpinner.start()
            startOutline()
        } else {
            launchSpinner.stop()
            stopOutline()
        }
        animatePress(launching, animated: animated)
        animateWash(launching, animated: animated)
    }

    private func animateWash(_ launching: Bool, animated: Bool) {
        launchWash.removeAnimation(forKey: "launchWash")
        let target: Float = launching ? 1 : 0
        launchWash.opacity = target
        guard animated else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = launching ? 0 : 1
        fade.toValue = target
        fade.duration = launching ? 0.30 : 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        launchWash.add(fade, forKey: "launchWash")
    }

    private func animatePress(_ pressing: Bool, animated: Bool) {
        guard let layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var target = CATransform3DIdentity
        if pressing {
            target = CATransform3DTranslate(target, center.x, center.y, 0)
            target = CATransform3DScale(target, 0.985, 0.985, 1)
            target = CATransform3DTranslate(target, -center.x, -center.y, 0)
            target = CATransform3DTranslate(target, 0, Theme.ls(1), 0)
        }

        let previous = layer.transform
        layer.transform = target
        guard animated else { return }

        let press = CASpringAnimation(keyPath: "transform")
        press.fromValue = previous
        press.toValue = target
        press.mass = 0.7
        press.stiffness = pressing ? 320 : 220
        press.damping = pressing ? 24 : 18
        press.duration = press.settlingDuration
        layer.add(press, forKey: "launchPress")
    }

    private func startOutline() {
        updateOutlinePaths()
        let now = CACurrentMediaTime()
        for (index, pulse) in launchPulses.enumerated() {
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

    private func stopOutline() {
        for pulse in launchPulses {
            pulse.removeAllAnimations()
            pulse.opacity = 0
        }
    }

    private func updateOutlinePaths() {
        let rect = bounds.insetBy(dx: Theme.ls(2), dy: Theme.ls(2))
        let path = CGPath(rect: rect, transform: nil)
        for pulse in launchPulses {
            pulse.path = path
        }
    }

    // MARK: - Drawing

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(rowIndex)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let result else { return }

        if isSelected || isLaunching {
            PixelDraw.fill(bounds, Theme.bgSelected)
            PixelDraw.fill(
                CGRect(x: 0, y: 0, width: Theme.ls(3), height: bounds.height),
                isLaunching ? Theme.success : Theme.accent
            )
        } else {
            PixelDraw.hLine(x: Theme.ls(52), y: bounds.maxY - Theme.ls(1), width: bounds.width - Theme.ls(52), color: Theme.line, thickness: max(1, Theme.ls(1)))
        }

        if isLaunching {
            drawConnectedLaunchFrame()
        }

        drawIcon(result)

        var titleRect = Layout.rowLabelRect(in: bounds)
        var subtitleRect = Layout.rowSubtitleRect(in: bounds)
        var launchLabelRect: CGRect?
        if isLaunching {
            let spinnerSize = Theme.ls(16)
            let spinnerX = bounds.width - Theme.ls(24) - spinnerSize
            let labelWidth = Theme.ls(88)
            let label = CGRect(
                x: spinnerX - Theme.ls(8) - labelWidth,
                y: Theme.ls(12),
                width: labelWidth,
                height: Theme.ls(12)
            )
            launchLabelRect = label
            let contentRight = label.minX - Theme.ls(8)
            titleRect.size.width = max(10, contentRight - titleRect.minX)
            subtitleRect.size.width = max(10, contentRight - subtitleRect.minX)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let title = NSMutableAttributedString(
            string: result.title,
            attributes: [
                .font: Theme.launcherDisplay(15),
                .foregroundColor: isLaunching ? Theme.success : Theme.text,
                .paragraphStyle: paragraph
            ]
        )
        if !isLaunching {
            for range in result.titleMatch where range.location + range.length <= title.length {
                title.addAttribute(.foregroundColor, value: Theme.accent, range: range)
            }
        }
        title.draw(in: titleRect)

        let subtitle = NSAttributedString(
            string: result.subtitle,
            attributes: [
                .font: Theme.launcherDisplay(9),
                .foregroundColor: isLaunching
                    ? Theme.success.withAlphaComponent(0.66)
                    : (isSelected ? Theme.textDim : Theme.textFaint),
                .paragraphStyle: paragraph
            ]
        )
        subtitle.draw(in: subtitleRect)

        if isLaunching, let launchLabelRect {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            ("LAUNCHING" as NSString).draw(
                in: launchLabelRect,
                withAttributes: [
                    .font: Theme.launcherDisplay(7.5),
                    .foregroundColor: Theme.success,
                    .paragraphStyle: paragraph
                ]
            )
        } else if isSelected {
            PixelDraw.chevron(x: bounds.width - Theme.ls(21), y: Theme.ls(16), unit: Theme.ls(2), color: Theme.accent)
        }
    }

    /// A single connected rectangle: 1 px sides and a thicker bottom edge,
    /// with overlapping corners so no gaps can appear.
    private func drawConnectedLaunchFrame() {
        let rect = bounds.insetBy(dx: Theme.ls(2), dy: Theme.ls(2))
        let side = max(1, Theme.ls(1))
        let bottom = max(1, Theme.ls(2))
        let color = Theme.success.withAlphaComponent(0.72)
        color.setFill()
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: side).fill()
        CGRect(x: rect.minX, y: rect.maxY - bottom, width: rect.width, height: bottom).fill()
        CGRect(x: rect.minX, y: rect.minY, width: side, height: rect.height).fill()
        CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: rect.height).fill()
    }

    private func drawIcon(_ result: SearchResult) {
        let box = CGRect(x: Theme.ls(18), y: Theme.ls(10), width: Theme.ls(22), height: Theme.ls(22))

        switch result.icon {
        case .file(let url):
            IconCache.shared.icon(for: url).draw(
                in: box,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )

        case .image(let url):
            if let image = IconCache.shared.image(at: url) {
                image.draw(
                    in: box,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else {
                PixelGlyph.globe.image(size: Theme.ls(16), color: Theme.textDim).draw(
                    in: CGRect(x: box.minX + Theme.ls(3), y: box.minY + Theme.ls(3), width: Theme.ls(16), height: Theme.ls(16))
                )
            }

        case .glyph(let glyph):
            PixelDraw.fill(box, Theme.bgRaised)
            PixelDraw.frame(
                box,
                thickness: max(1, Theme.ls(1)),
                color: isLaunching ? Theme.success : (isSelected ? Theme.accentDim : Theme.border),
                notch: Theme.ls(2)
            )
            glyph.image(size: Theme.ls(16), color: isLaunching ? Theme.success : (isSelected ? Theme.accent : Theme.textDim)).draw(
                in: CGRect(x: box.minX + Theme.ls(3), y: box.minY + Theme.ls(3), width: Theme.ls(16), height: Theme.ls(16)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }

        if isLaunching {
            PixelDraw.frame(
                box.insetBy(dx: -Theme.ls(2), dy: -Theme.ls(2)),
                thickness: max(1, Theme.ls(1)),
                color: Theme.success.withAlphaComponent(0.55),
                notch: Theme.ls(2)
            )
        }
    }
}
