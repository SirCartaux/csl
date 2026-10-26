import AppKit
import ApplicationServices
import QuartzCore
import ServiceManagement

/// The embedded character picker. CSL owns the menu bar icon, launch-at-login
/// and the app lifecycle; this object owns the Fn key, the floating panel and
/// the permission setup window.
public final class EmojiPickerFeature {
    public let brand: String

    private let store = EmojiStore.shared
    private var panel: CharacterPanel?
    private var viewController: PickerViewController?
    private var globeMonitor: GlobeKeyMonitor?
    private var lastExternalApp: NSRunningApplication?
    private var targetPID: pid_t = 0
    private var lastAnchor: CaretAnchor?
    private var mouseMonitor: Any?
    private var escapeMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var isClosing = false
    private var didStart = false
    private var didPrewarm = false

    public init(brand: String = "CSL") {
        self.brand = brand
    }

    deinit {
        stop()
    }

    // MARK: - Public state

    public var isVisible: Bool { panel?.isVisible == true }
    public var panelWindow: NSWindow? { panel }
    public var setupWindow: NSWindow? { SetupWindowController.shared.nsWindow }
    public var accessibilityGranted: Bool { CaretLocator.isTrusted }
    public var inputMonitoringGranted: Bool { GlobeKeyMonitor.inputMonitoringGranted() }
    public var fnDetection: String { globeMonitor?.sourceDescription ?? "WAITING" }
    public var systemGlobeKeyHandedOver: Bool { SystemGlobeKey.usageType() == 0 }

    public var needsSetup: Bool {
        !accessibilityGranted || !inputMonitoringGranted || !systemGlobeKeyHandedOver
    }

    public var statusSummary: String {
        let globe = systemGlobeKeyHandedOver ? "GLOBE READY" : "GLOBE SETUP"
        let ax = accessibilityGranted ? "A11Y OK" : "A11Y MISSING"
        let input = inputMonitoringGranted ? "INPUT OK" : "INPUT MISSING"
        return "\(fnDetection) · \(globe) · \(ax) · \(input)"
    }

    // MARK: - Lifecycle

    public func start(showSetupIfNeeded: Bool = true) {
        guard !didStart else { return }
        didStart = true
        AppPaths.prepare()
        store.load()
        buildPanel()
        installGlobalMonitors()
        installGlobeMonitor()
        observeWorkspace()
        prewarm()
        Log.debug("EmojiPickerFeature started (\(brand))")

        if showSetupIfNeeded, needsSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                self?.showSetup()
            }
        }
    }

    public func stop() {
        globeMonitor?.stop()
        globeMonitor = nil
        store.flush()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        mouseMonitor = nil
        escapeMonitor = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        SetupWindowController.shared.close()
        panel?.orderOut(nil)
        panel = nil
        viewController = nil
        didStart = false
        didPrewarm = false
    }

    // MARK: - Panel

    public func show() {
        guard let panel, let viewController else { return }
        if isClosing {
            panel.contentView?.layer?.removeAllAnimations()
            panel.contentView?.layer?.opacity = 1
            isClosing = false
        }
        if panel.isVisible {
            panel.makeKey()
            viewController.focus()
            return
        }

        let started = CACurrentMediaTime()
        captureTarget()
        viewController.prepareForShow()
        position(anchor: lastAnchor)

        panel.contentView?.layer?.removeAllAnimations()
        panel.contentView?.layer?.opacity = 1
        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        viewController.focus()
        if let layer = panel.contentView?.layer {
            InteractionMotion.appear(on: layer, duration: 0.09)
        }
        Log.debug(String(
            format: "emoji panel shown in %.1f ms (target pid %d, frame %@)",
            (CACurrentMediaTime() - started) * 1000,
            targetPID,
            NSStringFromRect(panel.frame)
        ))
    }

    /// Test / integration entry point. All arguments are optional.
    public func show(query: String? = nil, category: String? = nil, skinTone: Int? = nil) {
        show()
        guard let viewController else { return }
        if let category { viewController.setCategory(named: category) }
        if let query, !query.isEmpty { viewController.setSearchText(query) }
        if let skinTone { viewController.setSkinTone(skinTone) }
        viewController.focus()
    }

    public func hide() {
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        viewController?.prepareForHide()
        let finish = { [weak self] in
            guard let self else { return }
            self.panel?.orderOut(nil)
            self.panel?.contentView?.layer?.removeAllAnimations()
            self.panel?.contentView?.layer?.opacity = 1
            self.targetPID = 0
            self.isClosing = false
            Log.debug("emoji panel hidden")
        }

        if InteractionMotion.enabled, let layer = panel.contentView?.layer {
            InteractionMotion.disappear(on: layer, duration: 0.07)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: finish)
        } else {
            finish()
        }
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func showSetup() {
        hide()
        SetupWindowController.shared.brand = brand
        SetupWindowController.shared.show(
            status: currentSetupStatus(),
            actions: currentSetupActions()
        )
    }

    @discardableResult
    public func handOverGlobeKey() -> Bool {
        SystemGlobeKey.setToDoNothing()
    }

    // MARK: - Build

    private func buildPanel() {
        let viewController = PickerViewController()
        viewController.brand = brand
        viewController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: Theme.windowWidth,
            height: Theme.windowHeight
        )
        viewController.onClose = { [weak self] in
            self?.hide()
        }
        viewController.onInsert = { [weak self] item, text in
            self?.insert(item: item, text: text) ?? false
        }
        self.viewController = viewController

        let panel = CharacterPanel()
        panel.contentViewController = viewController
        panel.setContentSize(NSSize(width: Theme.windowWidth, height: Theme.windowHeight))
        self.panel = panel
        Log.debug("emoji panel built \(Theme.windowWidth)x\(Theme.windowHeight)")
    }

    private func prewarm() {
        guard let panel, let viewController, !didPrewarm else { return }
        didPrewarm = true
        viewController.prewarm()
        position(anchor: nil)
        panel.alphaValue = 0.01
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.contentView?.layer?.opacity = 1
        Log.debug("emoji panel prewarmed")
    }

    private func captureTarget() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = front
        }
        let preferred = lastExternalApp?.processIdentifier
        lastAnchor = CaretLocator.capture(preferredPID: preferred)

        var pid = lastAnchor?.pid ?? preferred ?? 0
        if pid == ProcessInfo.processInfo.processIdentifier {
            pid = preferred ?? 0
        }
        targetPID = pid
        Log.debug("emoji target: \(lastExternalApp?.localizedName ?? "nil") pid=\(pid) anchor=\(String(describing: lastAnchor?.axRect))")
    }

    private func position(anchor: CaretAnchor?) {
        guard let panel else { return }
        let frame = PickerPositioner.frame(anchor: anchor, windowSize: panel.frame.size)
        panel.setFrame(frame, display: false)
    }

    private func insert(item: EmojiItem, text: String) -> Bool {
        guard targetPID > 0,
              targetPID != ProcessInfo.processInfo.processIdentifier,
              NSRunningApplication(processIdentifier: targetPID) != nil else {
            TextInjector.copyToPasteboard(text)
            return false
        }
        let ok = TextInjector.insert(text, into: targetPID)
        if !ok {
            TextInjector.copyToPasteboard(text)
        }
        Log.debug("emoji insert \(item.text) -> pid \(targetPID) ok=\(ok)")
        return ok
    }

    // MARK: - Fn / Globe key

    private func installGlobeMonitor() {
        let monitor = GlobeKeyMonitor()
        monitor.onFnDown = {
            Log.debug("emoji Fn down")
        }
        monitor.onFnUp = { [weak self] usedAsModifier in
            guard !usedAsModifier else {
                Log.debug("emoji Fn released after modifier use — ignore")
                return
            }
            DispatchQueue.main.async {
                self?.toggle()
            }
        }
        monitor.start()
        globeMonitor = monitor
    }

    private func installGlobalMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self, self.isVisible else { return }
            let point = NSEvent.mouseLocation
            if !(self.panel?.frame.contains(point) ?? false) {
                self.hide()
            }
        }

        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.keyCode == 53 else { return }
            self.hide()
        }
    }

    private func observeWorkspace() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = front
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.lastExternalApp = app
            if self.isVisible, app.processIdentifier != self.targetPID {
                self.hide()
            }
        }
    }

    // MARK: - Setup

    private func currentSetupStatus() -> SetupStatus {
        SetupStatus(
            accessibility: accessibilityGranted,
            inputMonitoring: inputMonitoringGranted,
            fnUsageType: SystemGlobeKey.usageType(),
            fnSource: fnDetection,
            launchAtLogin: SMAppService.mainApp.status == .enabled
        )
    }

    private func currentSetupActions() -> SetupActions {
        SetupActions(
            requestAccessibility: { [weak self] in
                _ = CaretLocator.requestAccessibility()
                self?.refreshSetupSoon()
            },
            openAccessibility: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            },
            openInputMonitoring: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
                GlobeKeyMonitor.requestInputMonitoringIfNeeded()
            },
            openKeyboardSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            },
            disableGlobeKey: { [weak self] in
                let ok = SystemGlobeKey.setToDoNothing()
                self?.refreshSetupSoon()
                return ok
            },
            testPicker: { [weak self] in
                SetupWindowController.shared.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.show()
                }
            },
            toggleLaunchAtLogin: { [weak self] in
                self?.toggleLaunchAtLogin()
            },
            close: {
                SetupWindowController.shared.close()
            },
            statusProvider: { [weak self] in
                self?.currentSetupStatus() ?? SetupStatus(
                    accessibility: CaretLocator.isTrusted,
                    inputMonitoring: GlobeKeyMonitor.inputMonitoringGranted(),
                    fnUsageType: SystemGlobeKey.usageType(),
                    fnSource: "WAITING",
                    launchAtLogin: SMAppService.mainApp.status == .enabled
                )
            }
        )
    }

    private func refreshSetupSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            SetupWindowController.shared.refresh(status: self.currentSetupStatus())
        }
    }

    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.debug("emoji login item failed: \(error)")
        }
        refreshSetupSoon()
    }
}
