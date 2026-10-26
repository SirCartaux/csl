import AppKit
import QuartzCore

struct SetupStatus: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
    var fnUsageType: Int
    var fnSource: String
    var launchAtLogin: Bool
}

struct SetupActions {
    var requestAccessibility: () -> Void
    var openAccessibility: () -> Void
    var openInputMonitoring: () -> Void
    var openKeyboardSettings: () -> Void
    var disableGlobeKey: () -> Bool
    var testPicker: () -> Void
    var toggleLaunchAtLogin: () -> Void
    var close: () -> Void
    var statusProvider: (() -> SetupStatus)?
}

enum SetupLayout {
    static let windowWidth: CGFloat = 764
    static let windowHeight: CGFloat = 548
    static let inset: CGFloat = 32
    static let panelWidth: CGFloat = 700
    static let panelHeight: CGFloat = 484
    static let headerHeight: CGFloat = 32
    static let footerHeight: CGFloat = 28
    static let bodyPadding: CGFloat = 32
    static let rowHeight: CGFloat = 58
    static let rowTop: CGFloat = 16

    static func panelRect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: inset,
            y: inset,
            width: max(1, bounds.width - 2 * inset),
            height: max(1, bounds.height - 2 * inset)
        )
    }

    static func headerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: headerHeight)
    }

    static func footerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(
            x: panel.minX,
            y: panel.maxY - footerHeight,
            width: panel.width,
            height: footerHeight
        )
    }

    static func rowRect(index: Int, in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(
            x: panel.minX + bodyPadding,
            y: panel.minY + headerHeight + rowTop + CGFloat(index) * rowHeight,
            width: panel.width - 2 * bodyPadding,
            height: rowHeight
        )
    }

    static func rowButtonRect(index: Int, in bounds: CGRect) -> CGRect {
        let row = rowRect(index: index, in: bounds)
        return CGRect(x: row.maxX - 154, y: row.midY - 12, width: 154, height: 24)
    }

    static func footerTestRect(in bounds: CGRect) -> CGRect {
        let footer = footerRect(in: bounds)
        return CGRect(x: footer.maxX - bodyPadding - 206, y: footer.midY - 12, width: 118, height: 24)
    }

    static func footerCloseRect(in bounds: CGRect) -> CGRect {
        let footer = footerRect(in: bounds)
        return CGRect(x: footer.maxX - bodyPadding - 80, y: footer.midY - 12, width: 80, height: 24)
    }
}

/// The setup window is a sibling of the picker: same palette, same notched
/// chrome, same amber halo. It contains only things that need a human decision:
/// permissions, the system Globe-key takeover and launch-at-login.
final class SetupRootView: NSView {
    var logoText = "CEP SETUP" {
        didSet { needsDisplay = true }
    }
    var brand = "CEP" {
        didSet { needsDisplay = true }
    }
    var status = SetupStatus(
        accessibility: false,
        inputMonitoring: false,
        fnUsageType: 2,
        fnSource: "WAITING",
        launchAtLogin: false
    ) {
        didSet { needsDisplay = true }
    }

    var note: String? {
        didSet { needsDisplay = true }
    }

    var rowButtons: [PixelButton?] = []
    var footerButtons: [PixelButton] = []

    private let glowView = GlowView(frame: .zero)

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        glowView.panelRectProvider = { SetupLayout.panelRect(in: $0) }
        glowView.ledRectProvider = { panel in
            CGRect(x: panel.minX + 18, y: panel.minY + 14, width: 4, height: 4)
        }
        glowView.scale = 1
        addSubview(glowView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startGlow() {
        glowView.startPulse()
    }

    func stopGlow() {
        glowView.stopPulse()
    }

    override func layout() {
        super.layout()
        glowView.frame = bounds
        for (index, button) in rowButtons.enumerated() {
            button?.frame = SetupLayout.rowButtonRect(index: index, in: bounds)
        }
        if footerButtons.count == 2 {
            footerButtons[0].frame = SetupLayout.footerTestRect(in: bounds)
            footerButtons[1].frame = SetupLayout.footerCloseRect(in: bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let panel = SetupLayout.panelRect(in: bounds)
        PixelDraw.fill(panel.offsetBy(dx: 4, dy: 4), Theme.shadow)
        PixelDraw.fill(panel, Theme.bg)
        let borderColor = Theme.border.blended(withFraction: 0.16, of: Theme.accent) ?? Theme.border
        PixelDraw.frame(panel, thickness: 1, color: borderColor, notch: 3)

        drawHeader(panel: panel)
        drawRows(panel: panel)
        drawFooter(panel: panel)
    }

    private func drawHeader(panel: CGRect) {
        let rect = SetupLayout.headerRect(in: bounds)
        PixelDraw.fill(rect, Theme.bgRaised)
        PixelDraw.hLine(x: rect.minX, y: rect.maxY - 1, width: rect.width, color: Theme.line)
        PixelDraw.fill(
            CGRect(x: rect.minX + 18, y: rect.midY - 2, width: 4, height: 4),
            Theme.accent
        )

        let logoAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(15),
            .foregroundColor: Theme.accent
        ]
        let logo = logoText as NSString
        let logoSize = logo.size(withAttributes: logoAttributes)
        logo.draw(
            in: CGRect(
                x: rect.minX + 30,
                y: floor(rect.midY - logoSize.height / 2),
                width: logoSize.width + 4,
                height: logoSize.height
            ),
            withAttributes: logoAttributes
        )

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7.5),
            .foregroundColor: Theme.textFaint
        ]
        let subtitle = "PERMISSIONS & GLOBE KEY" as NSString
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        subtitle.draw(
            in: CGRect(
                x: rect.minX + 30 + logoSize.width + 12,
                y: floor(rect.midY - subtitleSize.height / 2),
                width: 320,
                height: subtitleSize.height
            ),
            withAttributes: subtitleAttributes
        )

        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8),
            .foregroundColor: Theme.textDim
        ]
        let key = "ESC" as NSString
        let keySize = key.size(withAttributes: keyAttributes)
        let capRect = CGRect(
            x: rect.maxX - keySize.width - 34,
            y: rect.minY + 9,
            width: keySize.width + 16,
            height: 14
        )
        PixelDraw.frame(capRect, thickness: 1, color: Theme.border, notch: 2)
        key.draw(
            in: CGRect(
                x: floor(capRect.midX - keySize.width / 2),
                y: floor(capRect.midY - keySize.height / 2),
                width: keySize.width + 2,
                height: keySize.height
            ),
            withAttributes: keyAttributes
        )
    }

    private func drawRows(panel: CGRect) {
        let rowTitles = [
            "ACCESSIBILITY",
            "INPUT MONITORING",
            "SYSTEM GLOBE KEY",
            "FN DETECTION",
            "LAUNCH AT LOGIN"
        ]
        let rowDescriptions = [
            "FIND THE TEXT CURSOR AND TYPE THE CHOSEN CHARACTER INSTANTLY",
            "READ THE FN KEY DIRECTLY FROM THE KEYBOARD'S HID REPORT",
            "SET TO DO NOTHING SO macOS DOES NOT OPEN ITS OWN EMOJI PICKER",
            "EVENT-DRIVEN, F1-F12 ARE IGNORED - NO KEY IS STOLEN",
            "START \(brand) WITH YOUR MAC"
        ]
        let rowStatuses = [
            status.accessibility ? ("GRANTED", Theme.success) : ("MISSING", Theme.danger),
            status.inputMonitoring ? ("GRANTED", Theme.success) : ("MISSING", Theme.danger),
            globeStatus(),
            fnStatus(),
            status.launchAtLogin ? ("ON", Theme.success) : ("OFF", Theme.textFaint)
        ]

        for index in rowTitles.indices {
            let row = SetupLayout.rowRect(index: index, in: bounds)
            let dotColor = rowStatuses[index].1
            PixelDraw.fill(
                CGRect(x: row.minX, y: row.midY - 3, width: 5, height: 6),
                dotColor
            )

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: Theme.displayBold(10),
                .foregroundColor: Theme.text
            ]
            let title = rowTitles[index] as NSString
            let titleSize = title.size(withAttributes: titleAttributes)
            title.draw(
                in: CGRect(x: row.minX + 16, y: row.minY + 8, width: 320, height: 13),
                withAttributes: titleAttributes
            )

            let statusAttributes: [NSAttributedString.Key: Any] = [
                .font: Theme.display(8),
                .foregroundColor: rowStatuses[index].1
            ]
            (rowStatuses[index].0 as NSString).draw(
                in: CGRect(
                    x: row.minX + 16 + titleSize.width + 12,
                    y: row.minY + 9,
                    width: 200,
                    height: 12
                ),
                withAttributes: statusAttributes
            )

            let descriptionAttributes: [NSAttributedString.Key: Any] = [
                .font: Theme.display(7),
                .foregroundColor: Theme.textFaint
            ]
            (rowDescriptions[index] as NSString).draw(
                in: CGRect(x: row.minX + 16, y: row.minY + 29, width: row.width - 190, height: 11),
                withAttributes: descriptionAttributes
            )

            PixelDraw.dottedLine(
                x: row.minX + 16,
                y: row.maxY - 1,
                width: row.width - 32,
                color: Theme.line,
                step: 5
            )
        }

        let infoY = SetupLayout.rowRect(index: 4, in: bounds).maxY + 12
        let infoAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7),
            .foregroundColor: Theme.textFaint
        ]
        let lines = [
            "THE CHARACTER PICKER NEVER READS YOUR TYPED TEXT. ACCESSIBILITY IS USED ONLY FOR THE CARET POSITION AND THE INJECTION.",
            "AFTER TAKING OVER THE GLOBE KEY, LOG OUT AND BACK IN (OR RESTART) TO APPLY THE SYSTEM SETTING."
        ]
        for (lineIndex, line) in lines.enumerated() {
            (line as NSString).draw(
                in: CGRect(
                    x: panel.minX + SetupLayout.bodyPadding,
                    y: infoY + CGFloat(lineIndex) * 13,
                    width: panel.width - 2 * SetupLayout.bodyPadding,
                    height: 11
                ),
                withAttributes: infoAttributes
            )
        }

        if let note {
            let noteAttributes: [NSAttributedString.Key: Any] = [
                .font: Theme.display(8.5),
                .foregroundColor: Theme.accent
            ]
            (note as NSString).draw(
                in: CGRect(
                    x: panel.minX + SetupLayout.bodyPadding,
                    y: infoY + 34,
                    width: panel.width - 2 * SetupLayout.bodyPadding,
                    height: 12
                ),
                withAttributes: noteAttributes
            )
        }
    }

    private func globeStatus() -> (String, NSColor) {
        switch status.fnUsageType {
        case 0: return ("DO NOTHING", Theme.success)
        case 1: return ("CHANGE INPUT SOURCE", Theme.accent)
        case 3: return ("START DICTATION", Theme.accent)
        default: return ("SHOWS EMOJI", Theme.accent)
        }
    }

    private func fnStatus() -> (String, NSColor) {
        switch status.fnSource {
        case "HID FN": return ("HID REPORT", Theme.success)
        case "EVENT TAP": return ("EVENT TAP", Theme.accent)
        default: return ("WAITING", Theme.danger)
        }
    }

    private func drawFooter(panel: CGRect) {
        let footer = SetupLayout.footerRect(in: bounds)
        PixelDraw.hLine(x: footer.minX, y: footer.minY, width: footer.width, color: Theme.line)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: Theme.textFaint
        ]
        ("ESC  CLOSE" as NSString).draw(
            in: CGRect(x: footer.minX + Theme.panelInset, y: footer.minY + 8, width: 160, height: 12),
            withAttributes: attributes
        )
    }
}

final class SetupWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupWindowController()

    private var window: SetupPanel?
    private var root: SetupRootView?
    var brand = "CEP"
    private var status = SetupStatus(
        accessibility: false,
        inputMonitoring: false,
        fnUsageType: 2,
        fnSource: "WAITING",
        launchAtLogin: false
    )
    private var actions: SetupActions?
    private var keyMonitor: Any?
    private var refreshTimer: Timer?

    private lazy var accessibilityButton = PixelButton(title: "REQUEST ACCESS", style: .accent)
    private lazy var inputButton = PixelButton(title: "OPEN SETTINGS")
    private lazy var globeButton = PixelButton(title: "TAKE OVER", style: .accent)
    private lazy var loginButton = PixelButton(title: "ENABLE")
    private lazy var testButton = PixelButton(title: "TEST PICKER", style: .accent)
    private lazy var closeButton = PixelButton(title: "CLOSE")

    var isVisible: Bool { window?.isVisible == true }
    var nsWindow: NSWindow? { window }

    func show(status: SetupStatus, actions: SetupActions) {
        self.status = status
        self.actions = actions
        let root = ensureWindow()
        refresh(status: status)
        root.startGlow()
        positionWindow()
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        installKeyMonitor()
        startRefreshTimer()
    }

    func refresh(status: SetupStatus) {
        self.status = status
        guard let root else { return }
        root.status = status
        refreshButtons()
        root.needsDisplay = true
        root.needsLayout = true
    }

    func close() {
        guard let window else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        root?.stopGlow()
        window.orderOut(nil)
        removeKeyMonitor()
    }

    private func ensureWindow() -> SetupRootView {
        if let root { return root }

        let panel = SetupPanel()
        let root = SetupRootView(frame: NSRect(
            x: 0,
            y: 0,
            width: SetupLayout.windowWidth,
            height: SetupLayout.windowHeight
        ))
        root.logoText = brand + " SETUP"
        root.brand = brand
        panel.contentView = root
        panel.setContentSize(NSSize(width: SetupLayout.windowWidth, height: SetupLayout.windowHeight))
        panel.delegate = self

        root.rowButtons = [accessibilityButton, inputButton, globeButton, nil, loginButton]
        root.footerButtons = [testButton, closeButton]
        for button in (root.rowButtons.compactMap { $0 } + root.footerButtons) {
            root.addSubview(button)
        }
        testButton.onClick = { [weak self] in
            self?.actions?.testPicker()
        }
        closeButton.onClick = { [weak self] in
            self?.actions?.close()
        }
        accessibilityButton.onClick = { [weak self] in
            guard let self else { return }
            if self.status.accessibility {
                self.actions?.openAccessibility()
            } else {
                self.actions?.requestAccessibility()
            }
        }
        inputButton.onClick = { [weak self] in
            self?.actions?.openInputMonitoring()
        }
        globeButton.onClick = { [weak self] in
            guard let self else { return }
            if self.status.fnUsageType == 0 {
                self.actions?.openKeyboardSettings()
            } else if self.actions?.disableGlobeKey() == true {
                self.status.fnUsageType = SystemGlobeKey.usageType()
                self.root?.note = "GLOBE KEY HANDED OVER / LOG OUT OR RESTART TO APPLY"
                self.refresh(status: self.status)
            } else {
                self.root?.note = "COULD NOT WRITE THE GLOBE KEY SETTING"
                self.root?.needsDisplay = true
            }
        }
        loginButton.onClick = { [weak self] in
            self?.actions?.toggleLaunchAtLogin()
        }

        window = panel
        self.root = root
        refreshButtons()
        return root
    }

    private func refreshButtons() {
        accessibilityButton.title = status.accessibility ? "OPEN SETTINGS" : "REQUEST ACCESS"
        accessibilityButton.style = status.accessibility ? .normal : .accent
        inputButton.style = status.inputMonitoring ? .normal : .accent
        globeButton.title = status.fnUsageType == 0 ? "OPEN KEYBOARD" : "TAKE OVER"
        globeButton.style = status.fnUsageType == 0 ? .normal : .accent
        loginButton.title = status.launchAtLogin ? "DISABLE" : "ENABLE"
        loginButton.style = .normal
    }

    private func positionWindow() {
        guard let window else { return }
        let screen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: floor(visible.midX - size.width / 2),
            y: floor(visible.midY - size.height / 2 + 20)
        )
        window.setFrameOrigin(origin)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let provider = self.actions?.statusProvider else { return }
            self.refresh(status: provider())
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}

private final class SetupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SetupLayout.windowWidth,
                height: SetupLayout.windowHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none
        level = .normal
        collectionBehavior = [.moveToActiveSpace]
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

