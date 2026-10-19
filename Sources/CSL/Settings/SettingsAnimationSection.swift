import AppKit

// MARK: - Pixel slider

final class PixelSlider: NSView {
    var minValue: Double = 0.25
    var maxValue: Double = 2.0

    var value: Double = 1.0 {
        didSet {
            value = min(max(value, minValue), maxValue)
            needsDisplay = true
        }
    }

    var onChange: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    private let segments = 28
    private let thumbWidth: CGFloat = 12
    private var isDragging = false

    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = CGRect(x: 0, y: 8, width: bounds.width, height: 12)
        let usable = max(1, track.width - thumbWidth)
        let normalized = CGFloat((value - minValue) / (maxValue - minValue))
        let thumbX = track.minX + normalized * usable

        for index in 0..<segments {
            let x = track.minX + CGFloat(index) * track.width / CGFloat(segments)
            let width = track.width / CGFloat(segments) - 2
            let rect = CGRect(x: x, y: track.minY + 2, width: max(1, width), height: track.height - 4)
            let active = x + width / 2 <= thumbX + 1
            PixelDraw.fill(rect, active ? Theme.accent : Theme.border.withAlphaComponent(0.45))
        }

        // Hairline baseline plus the square thumb.
        PixelDraw.hLine(x: 0, y: 27, width: bounds.width, color: Theme.line)
        let thumb = CGRect(x: thumbX, y: 3, width: thumbWidth, height: 22).integral
        PixelDraw.fill(thumb, Theme.bg)
        PixelDraw.frame(thumb, thickness: 1, color: Theme.accent, notch: 2)
        PixelDraw.fill(
            CGRect(x: thumb.minX + 3, y: thumb.minY + 3, width: thumb.width - 6, height: thumb.height - 6),
            Theme.accent
        )
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateValue(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValue(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onCommit?(value)
    }

    private func updateValue(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let usable = max(1, bounds.width - thumbWidth)
        let normalized = min(max((point.x - thumbWidth / 2) / usable, 0), 1)
        let newValue = minValue + Double(normalized) * (maxValue - minValue)
        value = newValue
        onChange?(value)
    }
}

// MARK: - Animation section

final class AnimationSection: SettingsSection {
    private let slider = PixelSlider()
    private let resetButton = ClosureButton("STANDARD 1,00X", style: .ghost) {}
    private let glowButton = ClosureButton("AN", style: .primary) {}
    private let glowIntensitySlider = PixelSlider()
    private let glowDurationSlider = PixelSlider()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        slider.minValue = SettingsStore.minPixelAnimationSpeed
        slider.maxValue = SettingsStore.maxPixelAnimationSpeed
        slider.onChange = { [weak self] _ in self?.needsDisplay = true }
        slider.onCommit = { value in SettingsStore.shared.setPixelAnimationSpeed(value) }
        addSubview(slider)

        resetButton.setAction { [weak self] in
            SettingsStore.shared.setPixelAnimationSpeed(SettingsStore.defaultPixelAnimationSpeed)
            self?.reload()
        }
        addSubview(resetButton)

        glowButton.setAction { [weak self] in
            SettingsStore.shared.setResultGlowEnabled(!SettingsStore.shared.resultGlowEnabled)
            self?.reload()
        }
        addSubview(glowButton)

        glowIntensitySlider.minValue = 0.1
        glowIntensitySlider.maxValue = 1.0
        glowIntensitySlider.onChange = { [weak self] _ in self?.needsDisplay = true }
        glowIntensitySlider.onCommit = { value in
            SettingsStore.shared.setResultGlowIntensity(value)
        }
        addSubview(glowIntensitySlider)

        glowDurationSlider.minValue = 0.12
        glowDurationSlider.maxValue = 0.8
        glowDurationSlider.onChange = { [weak self] _ in self?.needsDisplay = true }
        glowDurationSlider.onCommit = { value in
            SettingsStore.shared.setResultGlowDuration(value)
        }
        addSubview(glowDurationSlider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        slider.frame = CGRect(x: 0, y: 104, width: min(380, bounds.width), height: 30)
        resetButton.frame = CGRect(x: 0, y: 276, width: 180, height: 28)
        glowButton.frame = CGRect(x: 0, y: 332, width: 70, height: 28)
        glowIntensitySlider.frame = CGRect(x: 0, y: 390, width: min(220, bounds.width), height: 26)
        glowDurationSlider.frame = CGRect(x: 0, y: 462, width: min(220, bounds.width), height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(
            title: "ANIMATION",
            subtitle: "BEWEGUNG, LICHT UND GESCHWINDIGKEIT."
        )

        drawText("GESCHWINDIGKEIT", x: 0, y: 64, width: 220, font: 8.5, color: Theme.textDim)
        drawText(speedText(slider.value), x: bounds.width - 120, y: 60, width: 120, font: 14, color: Theme.accent, bold: true, align: .right)

        drawText("LANGSAM", x: 0, y: 140, width: 90, font: 8, color: Theme.textFaint)
        drawText("SCHNELL", x: bounds.width - 90, y: 140, width: 90, font: 8, color: Theme.textFaint, align: .right)
        drawText("0,25X", x: 92, y: 140, width: 50, font: 8, color: Theme.textFaint)
        drawText("2,0X", x: bounds.width - 142, y: 140, width: 50, font: 8, color: Theme.textFaint, align: .right)

        PixelDraw.hLine(x: 0, y: 176, width: bounds.width, color: Theme.line)

        drawText("SANFTER ZOOM UND FADE BEIM OEFFNEN UND SCHLIESSEN.",
                 x: 0, y: 196, width: bounds.width, font: 8, color: Theme.textFaint)
        drawText("NEUE ERGEBNISSE BEKOMMEN EINEN KURZEN GLOW, NUR DIE NEUEN ZEILEN.",
                 x: 0, y: 214, width: bounds.width, font: 8, color: Theme.textFaint)
        drawText("REDUZIERTE BEWEGUNG IN MACOS WIRD BERUECKSICHTIGT.",
                 x: 0, y: 232, width: bounds.width, font: 8, color: Theme.textFaint)

        drawText("1,00X IST DER STANDARD.", x: 194, y: 284, width: bounds.width - 194, font: 8, color: Theme.textFaint)

        PixelDraw.hLine(x: 0, y: 304, width: bounds.width, color: Theme.line)
        drawText("ERGEBNIS-GLOW", x: 0, y: 312, width: 220, font: 8.5, color: Theme.textDim)
        drawText("GLOW BEI NEUEN ERGEBNISZEILEN.", x: 84, y: 338, width: bounds.width - 84, font: 8, color: Theme.textFaint)

        drawText("INTENSITÄT", x: 0, y: 372, width: 160, font: 8, color: Theme.textFaint)
        drawText(intensityText(glowIntensitySlider.value), x: bounds.width - 100, y: 370, width: 100, font: 9, color: Theme.accent, bold: true, align: .right)
        drawText("SCHWACH", x: 0, y: 424, width: 90, font: 7.5, color: Theme.textFaint)
        drawText("STARK", x: 160, y: 424, width: 60, font: 7.5, color: Theme.textFaint, align: .right)

        drawText("ABKLINGZEIT", x: 0, y: 446, width: 160, font: 8, color: Theme.textFaint)
        drawText(durationText(glowDurationSlider.value), x: bounds.width - 100, y: 444, width: 100, font: 9, color: Theme.accent, bold: true, align: .right)
        drawText("SCHNELL", x: 0, y: 496, width: 90, font: 7.5, color: Theme.textFaint)
        drawText("LANGSAM", x: 160, y: 496, width: 60, font: 7.5, color: Theme.textFaint, align: .right)
    }

    override func reload() {
        slider.value = SettingsStore.shared.pixelAnimationSpeed
        glowButton.title = SettingsStore.shared.resultGlowEnabled ? "AN" : "AUS"
        glowButton.style = SettingsStore.shared.resultGlowEnabled ? .primary : .ghost
        glowButton.needsDisplay = true
        glowIntensitySlider.value = SettingsStore.shared.resultGlowIntensity
        glowDurationSlider.value = SettingsStore.shared.resultGlowDuration
        needsDisplay = true
    }

    private func speedText(_ speed: Double) -> String {
        let formatted = String(format: "%.2f", speed).replacingOccurrences(of: ".", with: ",")
        return "\(formatted)X"
    }

    private func intensityText(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private func durationText(_ value: Double) -> String {
        String(format: "%.2f S", value).replacingOccurrences(of: ".", with: ",")
    }
}
