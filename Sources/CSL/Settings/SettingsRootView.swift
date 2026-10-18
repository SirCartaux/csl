import AppKit

final class SettingsRootView: NSView {
    let sidebar = SettingsSidebarView()
    let contentContainer = NSView()
    let closeButton = PixelButton("X", style: .ghost)
    let glowView = GlowView(frame: .zero)

    var onClose: (() -> Void)?

    private var isDragging = false
    private var dragWindowOrigin: NSPoint = .zero
    private var dragMouseOrigin: NSPoint = .zero

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        addSubview(sidebar)
        addSubview(contentContainer)

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        addSubview(closeButton)

        glowView.panelRectProvider = { bounds in
            bounds.insetBy(dx: Theme.settingsInset, dy: Theme.settingsInset)
        }
        glowView.ledRectProvider = nil
        addSubview(glowView)
    }

    @objc private func closePressed() {
        onClose?()
    }

    func startGlow() {
        glowView.startPulse()
    }

    func stopGlow() {
        glowView.stopPulse()
    }

    override func layout() {
        super.layout()
        let panel = SettingsLayout.panelRect(in: bounds)
        sidebar.frame = SettingsLayout.sidebarRect(in: bounds)
        contentContainer.frame = SettingsLayout.bodyRect(in: bounds)
        closeButton.frame = CGRect(
            x: panel.maxX - 42,
            y: panel.minY + 11,
            width: 28,
            height: 26
        )
        glowView.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let panel = SettingsLayout.panelRect(in: bounds)

        PixelDraw.fill(panel.offsetBy(dx: 6, dy: 6), Theme.shadow)
        PixelDraw.fill(panel, Theme.bg)
        let borderColor = Theme.border.blended(withFraction: 0.16, of: Theme.accent) ?? Theme.border
        PixelDraw.frame(panel, thickness: 1, color: borderColor, notch: 3)

        let header = SettingsLayout.headerRect(in: bounds)
        PixelDraw.fill(header, Theme.bgRaised)
        PixelDraw.hLine(x: header.minX, y: header.maxY - 1, width: header.width, color: Theme.line)

        PixelDraw.fill(CGRect(x: panel.minX + 20, y: panel.minY + 22, width: 4, height: 4), Theme.accent)

        let logoAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(17),
            .foregroundColor: Theme.accent
        ]
        let logoSize = ("CSL" as NSString).size(withAttributes: logoAttributes)
        ("CSL" as NSString).draw(
            in: CGRect(x: panel.minX + 34, y: panel.minY + 15, width: logoSize.width + 4, height: 20),
            withAttributes: logoAttributes
        )
        ("SETTINGS" as NSString).draw(
            in: CGRect(
                x: panel.minX + 34 + logoSize.width + 12,
                y: panel.minY + 21,
                width: 120,
                height: 14
            ),
            withAttributes: [
                .font: Theme.display(9),
                .foregroundColor: Theme.textFaint
            ]
        )

        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8),
            .foregroundColor: Theme.textFaint
        ]
        let hintSize = ("ESC" as NSString).size(withAttributes: hintAttributes)
        ("ESC" as NSString).draw(
            in: CGRect(
                x: panel.maxX - 54 - hintSize.width,
                y: panel.minY + 20,
                width: hintSize.width + 2,
                height: 12
            ),
            withAttributes: hintAttributes
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if SettingsLayout.headerRect(in: bounds).contains(point) {
            guard let window else { return }
            isDragging = true
            dragWindowOrigin = window.frame.origin
            dragMouseOrigin = NSEvent.mouseLocation
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging, let window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: dragWindowOrigin.x + (current.x - dragMouseOrigin.x),
            y: dragWindowOrigin.y + (current.y - dragMouseOrigin.y)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }
}
