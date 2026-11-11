import AppKit
import ApplicationServices
import CEPKit
import QuartzCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, SearchEngineDelegate {
    private let engine = SearchEngine()
    private var panel: SearchPanel!
    private var viewController: SearchViewController!
    private var launchInProgress = false
    private var launchCompletionScheduled = false
    private var activeLaunchID: UUID?
    private let applicationWindowWaiter = ApplicationWindowWaiter()
    private var hideCompletion: (() -> Void)?
    private var pasteAccessibilityRequested = false
    private var lastExternalApp: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    private var hotkeyManager: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var emojiPicker: EmojiPickerFeature?

    private var snapshotPath: String?
    private var queryArgument: String?
    private var selftestTerm: String?
    private var benchTerms: [String] = []
    private var indexTestFolder: String?
    private var iconTestURL: String?
    private var settingsSnapshotPath: String?
    private var settingsTabArgument: String?
    private var settingsAtLaunch = false
    private var reindexAtLaunch = false
    private var snapshotDelay: TimeInterval = 1.0
    private var menuTest = false
    private var dragTest = false
    private var watchTestFolder: String?
    private var watchCheckFolder: String?
    private var rankTest = false
    private var scaleArgument: CGFloat?
    private var selftestStarted: CFTimeInterval = 0
    private var didLogSelftestFirstUpdate = false
    private var isClosing = false
    private var settingsShortcutMonitor: Any?
    private var outsideClickTap: CFMachPort?
    private var outsideClickRunLoopSource: CFRunLoopSource?
    private var outsideClickReplayScheduled = false
    private var suppressOriginalMouseUp = false
    private var pasteKeyMonitor: Any?

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        PixelFont.registerBundledFonts()
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        parseArguments()
        _ = SettingsStore.shared
        _ = ShortcutStore.shared
        applyInitialLauncherScale()
        buildPanel()
        buildStatusItem()
        installHotkey()
        installSettingsShortcut()
        ClipboardHistoryStore.shared.start()
        installPasteKeyMonitor()

        engine.delegate = self
        engine.warmUp()

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
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.lastExternalApp = app
        }

        FileIndex.shared.loadAsync {
            FileWatcher.shared.sync()
        }
        ResultRanker.shared.loadAsync()
        FaviconService.shared.prefetchMissing()
        observeSettings()

        if let path = ProcessInfo.processInfo.environment["CSL_CLIPBOARD_SNAPSHOT"], !path.isEmpty {
            showPanel()
            viewController.enterClipboardMode()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.writeSnapshot(to: path)
                NSApp.terminate(nil)
            }
            return
        }

        if let path = settingsSnapshotPath {
            SettingsWindowController.shared.show(tab: parsedSettingsTab())
            if reindexAtLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    IndexCoordinator.shared.indexAll()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
                self?.writeSnapshot(window: SettingsWindowController.shared.nsWindow, to: path)
                NSApp.terminate(nil)
            }
        } else if settingsAtLaunch {
            SettingsWindowController.shared.show(tab: parsedSettingsTab())
            if reindexAtLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    IndexCoordinator.shared.indexAll()
                }
            }
            if CommandLine.arguments.contains("--focus-url") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    SettingsWindowController.shared.focusWebsiteURLField()
                }
            }
        } else if rankTest {
            runRankTest()
        } else if menuTest || dragTest {
            runContextTest()
        } else if let folder = watchTestFolder {
            runWatchTest(folder)
        } else if watchCheckFolder != nil {
            runWatchCheck()
        } else if let folder = indexTestFolder {
            runIndexTest(folder)
        } else if let url = iconTestURL {
            runIconTest(url)
        } else if let term = selftestTerm {
            runSelfTest(term)
        } else if !benchTerms.isEmpty {
            runBench()
        } else if snapshotPath != nil {
            runSnapshot()
        } else {
            if CommandLine.arguments.contains("--show") {
                showPanel()
                if let queryArgument, !queryArgument.isEmpty {
                    viewController.setSearchText(queryArgument)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.prewarm()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                IndexCoordinator.shared.indexMissing()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            ShortcutIconService.shared.prefetchMissing()
        }

        if shouldStartEmojiPicker() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.startEmojiPicker()
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        emojiPicker?.stop()
        if let settingsShortcutMonitor {
            NSEvent.removeMonitor(settingsShortcutMonitor)
        }
        if let pasteKeyMonitor {
            NSEvent.removeMonitor(pasteKeyMonitor)
        }
        removeOutsideClickTap()
        ClipboardHistoryStore.shared.stop()
        ClipboardHistoryStore.shared.flush()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        FileWatcher.shared.stopAll()
        FileIndex.shared.flush()
        ResultRanker.shared.flush()
    }

    // MARK: - Text editing

    private func buildMainMenu() {
        let main = NSMenu(title: "CSL")
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "CSL")
        main.addItem(appItem)

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")

        let undo = NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        undo.target = nil
        edit.addItem(undo)

        let redo = NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = nil
        edit.addItem(redo)
        edit.addItem(.separator())

        for (title, action, key) in [
            ("Cut", NSSelectorFromString("cut:"), "x"),
            ("Copy", NSSelectorFromString("copy:"), "c"),
            ("Paste", NSSelectorFromString("paste:"), "v"),
            ("Select All", NSSelectorFromString("selectAll:"), "a")
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = nil
            edit.addItem(item)
        }

        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// A menu key equivalent normally handles this, but CSL's non-activating
    /// panels do not always get first crack at the app menu. This keeps Cmd+V
    /// working in every field editor in the launcher, settings, picker and
    /// modal prompts.
    private func installPasteKeyMonitor() {
        guard pasteKeyMonitor == nil else { return }
        pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v" else {
                return event
            }
            let keyWindow = NSApp.windows.first(where: { $0.isKeyWindow }) ?? NSApp.keyWindow
            guard let responder = keyWindow?.firstResponder,
                  responder is NSTextView || responder is NSTextField else {
                return event
            }
            if NSApp.sendAction(NSSelectorFromString("paste:"), to: responder, from: nil) {
                return nil
            }
            return event
        }
    }

    // MARK: - UI setup

    private func buildPanel() {
        viewController = SearchViewController()
        viewController.engine = engine
        viewController.view.frame = NSRect(
            x: 0,
            y: 0,
            width: Theme.panelWidth + 2 * Theme.panelInset,
            height: 360
        )
        viewController.onClose = { [weak self] in
            self?.hidePanel(restoreFocus: true)
        }
        viewController.onChoose = { [weak self] result, reveal in
            self?.perform(result, reveal: reveal)
        }
        viewController.onPaste = { [weak self] in
            self?.pasteClipboardIntoFocusedApp()
        }
        viewController.onDragDismiss = { [weak self] in
            guard let self else { return }
            self.viewController.cancelPendingOpen()
            self.viewController.stopGlow()
            self.engine.cancel()
            self.panel.orderOut(nil)
        }
        viewController.onDragOut = { [weak self] result in
            guard let self else { return }
            ResultRanker.shared.record(result, query: self.engine.lastQuery, revealed: false)
        }

        panel = SearchPanel()
        panel.delegate = self
        panel.contentViewController = viewController
        panel.setContentSize(NSSize(
            width: Theme.panelWidth + 2 * Theme.panelInset,
            height: viewController.preferredContentHeight + 2 * Theme.panelInset
        ))
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = PixelGlyph.search.image(size: 20, color: .black)
            image.isTemplate = true
            button.image = image
            button.toolTip = "CSL — Command Search Launcher"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func observeSettings() {
        let center = NotificationCenter.default
        center.addObserver(forName: .cslOpenSettings, object: nil, queue: .main) { [weak self] _ in
            self?.hidePanel(restoreFocus: false)
            self?.showSettings()
        }
        center.addObserver(forName: .cslOpenClipboardHistory, object: nil, queue: .main) { [weak self] _ in
            self?.showClipboardHistory()
        }
        for name in [Notification.Name.cslIndexLoaded, .cslIndexFinished] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.engine.refreshIndexResults()
            }
        }
        center.addObserver(forName: .cslSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.engine.refresh()
            FileWatcher.shared.sync()
        }
    }

    private func showSettings() {
        hidePanel(restoreFocus: false)
        SettingsWindowController.shared.show()
    }

    private func parsedSettingsTab() -> SettingsTab {
        guard let raw = settingsTabArgument?.lowercased(),
              let tab = SettingsTab(rawValue: raw) else {
            return .folders
        }
        return tab
    }

    private func installSettingsShortcut() {
        guard settingsShortcutMonitor == nil else { return }
        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command), flags.contains(.shift),
               event.keyCode == 9, // V
               self.panel.isVisible {
                self.viewController.toggleClipboardMode()
                return nil
            }
            guard flags.contains(.command),
                  event.keyCode == 43, // comma
                  self.panel.isVisible else { return event }
            self.hidePanel(restoreFocus: false)
            self.showSettings()
            return nil
        }
    }

    private func installHotkey() {
        let manager = HotkeyManager()
        manager.onTrigger = { [weak self] in
            self?.togglePanel()
        }
        manager.install()
        hotkeyManager = manager
    }

    /// Create the window server surface ahead of time so the first ⌘Space is as
    /// fast as the hundredth. Alpha stays near zero, so nothing flashes.
    private func prewarm() {
        guard panel != nil, !panel.isVisible else { return }
        viewController.prepareForPresentation()
        position(panel)
        viewController.prewarmPixelAnimations()
        panel.alphaValue = 0.01
        panel.orderFrontRegardless()
        panel.orderOut(nil)
        panel.alphaValue = 1
        Log.debug("panel prewarmed")
    }

    // MARK: - Show / hide

    private func togglePanel() {
        if isClosing {
            showPanel()
            return
        }
        if panel.isVisible {
            hidePanel(restoreFocus: true)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        if SettingsWindowController.shared.isVisible {
            SettingsWindowController.shared.close(restoreFocus: false)
        }
        if emojiPicker?.isVisible == true {
            emojiPicker?.hide(animated: false)
        }
        if isClosing {
            // Interrupt closing and resume interaction immediately.
            viewController.cancelPixelAnimations()
            viewController.restoreLaunchPresentation()
            viewController.startGlow()
            isClosing = false
        }
        guard !panel.isVisible else {
            panel.makeKey()
            viewController.focus()
            return
        }

        let started = CACurrentMediaTime()
        let screen = screenUnderMouse()
        let safeScale = safeLauncherScale(Theme.launcherScale, for: screen)
        if abs(safeScale - Theme.launcherScale) > 0.0001 {
            viewController.applyLauncherScale(safeScale)
        }
        viewController.prepareForPresentation()
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = front
        }
        position(panel, on: screen)
        // Prepare the entrance before the panel appears.
        viewController.preparePixelOpen()
        // Deliberately no NSApp.activate(): the non-activating panel becomes
        // key while the previous app stays frontmost, Spotlight-style.
        panel.makeKeyAndOrderFront(nil)
        viewController.focus()
        viewController.startPixelOpen()
        viewController.startGlow()
        outsideClickReplayScheduled = false
        suppressOriginalMouseUp = false
        refreshOutsideClickTap()
        Log.debug(String(format: "panel shown in %.1f ms", (CACurrentMediaTime() - started) * 1000))
    }

    func hidePanel(restoreFocus: Bool, completion: (() -> Void)? = nil) {
        guard panel.isVisible, !isClosing else { return }
        launchInProgress = false
        launchCompletionScheduled = false
        activeLaunchID = nil
        applicationWindowWaiter.cancel()
        hideCompletion = completion
        isClosing = true
        viewController.cancelPendingOpen()
        viewController.dismissQuickLook()
        viewController.stopGlow()
        engine.cancel()
        viewController.animatePixelClose { [weak self] in
            self?.finishHide(restoreFocus: restoreFocus)
        }
    }

    private func finishHide(restoreFocus: Bool) {
        guard isClosing else { return }
        panel.orderOut(nil)
        viewController.restoreLaunchPresentation()
        viewController.cancelPixelAnimations()
        isClosing = false
        Log.debug("panel hidden (restoreFocus: \(restoreFocus))")
        if restoreFocus {
            panel.resignKey()
            // Only relevant when the panel was opened from the menu bar (which
            // does activate the app). The hotkey path is non-activating.
            if NSApp.isActive {
                NSApp.hide(nil)
            }
        }
        refreshOutsideClickTap()
        let completion = hideCompletion
        hideCompletion = nil
        completion?()
    }

    private func position(_ window: NSWindow, on targetScreen: NSScreen? = nil) {
        let screen = targetScreen ?? screenUnderMouse()
        let visible = screen.visibleFrame
        let size = window.frame.size

        let x = visible.midX - size.width / 2
        let topGap = max(48, visible.height * 0.13)
        // The panel sits Theme.panelInset below the window top edge.
        let y = visible.maxY - size.height - topGap + Theme.panelInset
        var frame = window.frame
        frame.origin = NSPoint(x: floor(x), y: floor(y))
        let margin: CGFloat = 8
        frame.origin.x = min(max(frame.minX, visible.minX + margin), visible.maxX - margin - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY + margin), visible.maxY - margin - frame.height)
        window.setFrameOrigin(NSPoint(x: floor(frame.minX), y: floor(frame.minY)))
    }

    private func safeLauncherScale(_ requested: CGFloat, for screen: NSScreen) -> CGFloat {
        let visible = screen.visibleFrame
        let baseWidth = 700 + 2 * 32
        let baseHeight = 32 + 54 + 28 + 7 * 42 + 2 * 32
        let maxByWidth = (visible.width - 16) / CGFloat(baseWidth)
        let maxByHeight = (visible.height - 16) / CGFloat(baseHeight)
        let maximum = max(Theme.minLauncherScale,
                          min(Theme.maxLauncherScale, maxByWidth, maxByHeight))
        return min(max(requested, Theme.minLauncherScale), maximum)
    }

    private func applyInitialLauncherScale() {
        let stored = CGFloat(SettingsStore.shared.settings.launcherScale ?? 1)
        var scale = min(max(stored, Theme.minLauncherScale), Theme.maxLauncherScale)
        if let override = scaleArgument {
            scale = min(max(override, Theme.minLauncherScale), Theme.maxLauncherScale)
        }
        if let screen = NSScreen.main {
            scale = safeLauncherScale(scale, for: screen)
        }
        Theme.launcherScale = scale
        Log.debug(String(format: "launcher scale at launch: %.3f", scale))
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    // MARK: - Actions

    private func perform(_ result: SearchResult, reveal: Bool) {
        if case .complete(let text) = result.action {
            viewController.fillSearchInput(text)
            return
        }
        guard !launchInProgress else { return }
        launchInProgress = true
        launchCompletionScheduled = false
        let launchID = UUID()
        activeLaunchID = launchID
        let isolatingOpenedResult: Bool
        if case .open = result.action {
            isolatingOpenedResult = !reveal
        } else {
            isolatingOpenedResult = false
        }
        viewController.markLaunching(result, isolate: isolatingOpenedResult)

        let started = CACurrentMediaTime()
        let query = engine.lastQuery

        // Opened items finish when their app has a window, with no artificial
        // minimum delay. Other actions retain their brief launch feedback.
        func finish(_ success: Bool, record: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeLaunchID == launchID, self.launchInProgress, !self.launchCompletionScheduled else { return }
                self.launchCompletionScheduled = true
                let remaining = isolatingOpenedResult ? 0 : max(0, 1.0 - (CACurrentMediaTime() - started))
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                    guard let self, self.activeLaunchID == launchID, self.launchInProgress else { return }
                    self.launchInProgress = false
                    self.launchCompletionScheduled = false
                    self.activeLaunchID = nil
                    self.applicationWindowWaiter.cancel()
                    self.viewController.finishLaunching(success: success)
                    if success {
                        if record {
                            ResultRanker.shared.record(result, query: query, revealed: reveal)
                            if result.kind == .website, !reveal {
                                QuerySuggestionHistory.shared.recordSuccessful(result, raw: query)
                            }
                        }
                        self.hidePanel(restoreFocus: false)
                    } else {
                        self.panel.makeKeyAndOrderFront(nil)
                        self.viewController.focus()
                    }
                }
            }
        }

        switch result.action {
        case .open(let url):
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                finish(true, record: true)
            } else if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(
                    at: url,
                    configuration: configuration
                ) { [weak self] application, error in
                    DispatchQueue.main.async {
                        guard let self, self.activeLaunchID == launchID, self.launchInProgress else { return }
                        guard error == nil, let application else {
                            finish(false, record: false)
                            return
                        }
                        self.applicationWindowWaiter.wait(for: application) { success in
                            finish(success, record: true)
                        }
                    }
                }
            } else {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open(
                    url,
                    configuration: configuration
                ) { [weak self] application, error in
                    DispatchQueue.main.async {
                        guard let self, self.activeLaunchID == launchID, self.launchInProgress else { return }
                        guard error == nil else { finish(false, record: false); return }
                        if let application {
                            self.applicationWindowWaiter.wait(for: application) { success in
                                finish(success, record: true)
                            }
                        } else {
                            // Some URL handlers acknowledge opening without
                            // returning a process that exposes a window.
                            finish(true, record: true)
                        }
                    }
                }
            }

        case .reveal(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            finish(true, record: true)

        case .manage(let command, let program):
            Task { @MainActor in
                let success = await ProcessActionRunner.run(command, program: program)
                finish(success, record: false)
            }

        case .complete:
            finish(false, record: false) // Handled before starting launch feedback.

        case .run(let action):
            action()
            finish(true, record: false)
        }
    }

    // MARK: - Clipboard paste

    private func pasteClipboardIntoFocusedApp() {
        guard AXIsProcessTrusted() else {
            if !pasteAccessibilityRequested {
                pasteAccessibilityRequested = true
                let options = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            viewController.flashStatus("ACCESSIBILITY FOR PASTE")
            return
        }

        let target = lastExternalApp
        hidePanel(restoreFocus: true) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                if let target, !target.isTerminated {
                    _ = target.activate(options: [])
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    self.postPasteKeystroke(to: target)
                }
            }
        }
    }

    private func postPasteKeystroke(to target: NSRunningApplication?) {
        guard AXIsProcessTrusted() else {
            viewController.flashStatus("ACCESSIBILITY FOR PASTE")
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand

        let front = NSWorkspace.shared.frontmostApplication
        Log.debug("clipboard paste focus: \(front?.localizedName ?? "nil") target: \(target?.localizedName ?? "nil")")
        down?.post(tap: .cghidEventTap)
        usleep(30_000)
        up?.post(tap: .cghidEventTap)
        Log.debug("clipboard paste sent")
    }

    // MARK: - Window delegate

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === panel, panel.isVisible, !isClosing else { return }
        // Launching an app naturally moves key focus to it; keep CSL visible
        // until a visible application window has actually been detected.
        if launchInProgress { return }
        if viewController.isPresentingAliasPrompt { return }
        // A drag out of the panel temporarily takes key away; hide only after
        // the drag session has ended.
        if viewController.isDraggingResult || viewController.isPreviewing { return }

        // Clicks outside the panel are intercepted by the event tap while it
        // is installed, so the panel normally does not resign for them. Any
        // other key loss (Cmd+Tab, a menu, another CSL window) keeps the old
        // close behaviour.
        hidePanel(restoreFocus: false)
    }

    // MARK: - Outside click-through

    private static let outsideClickTapCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
        return delegate.handleOutsideClickTap(type: type, event: event)
    }

    private func handleOutsideClickTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let outsideClickTap {
                CGEvent.tapEnable(tap: outsideClickTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard panel.isVisible || (emojiPicker?.isVisible ?? false),
              !viewController.isPresentingAliasPrompt,
              !viewController.isDraggingResult,
              !viewController.isPreviewing else {
            return Unmanaged.passUnretained(event)
        }

        let point = NSEvent.mouseLocation
        guard !isPointCoveredByCSLWindow(point) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown:
            // Swallow the original down/up so the target receives exactly one
            // click: the synthetic replay after the panel is gone.
            suppressOriginalMouseUp = true
            guard !outsideClickReplayScheduled else { return nil }
            let location = event.location
            DispatchQueue.main.async { [weak self] in
                self?.handleOutsideClick(at: location, replay: true)
            }
            return nil
        case .leftMouseUp:
            if suppressOriginalMouseUp {
                suppressOriginalMouseUp = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func refreshOutsideClickTap() {
        let shouldInstall = panel.isVisible || (emojiPicker?.isVisible ?? false)
        if shouldInstall {
            if outsideClickTap == nil { installOutsideClickTap() }
        } else {
            removeOutsideClickTap()
        }
        emojiPicker?.outsideClickThroughEnabled = outsideClickTap != nil
    }

    private func installOutsideClickTap() {
        removeOutsideClickTap()
        guard AXIsProcessTrusted() else {
            Log.debug("outside click-through: accessibility permission missing")
            return
        }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.outsideClickTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            Log.debug("outside click-through: could not create event tap")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        outsideClickTap = tap
        outsideClickRunLoopSource = source
        Log.debug("outside click-through: event tap installed")
    }

    private func removeOutsideClickTap() {
        if let outsideClickRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), outsideClickRunLoopSource, .commonModes)
        }
        if let outsideClickTap {
            CGEvent.tapEnable(tap: outsideClickTap, enable: false)
            CFMachPortInvalidate(outsideClickTap)
        }
        outsideClickRunLoopSource = nil
        outsideClickTap = nil
        suppressOriginalMouseUp = false
        emojiPicker?.outsideClickThroughEnabled = false
    }

    private func isPointCoveredByCSLWindow(_ point: NSPoint) -> Bool {
        if panel.frame.contains(point) { return true }
        for window in NSApp.windows where window.isVisible && window !== panel {
            if window.frame.contains(point) { return true }
        }
        return false
    }

    private func handleOutsideClick(at location: CGPoint, replay: Bool) {
        guard !outsideClickReplayScheduled else { return }
        let panelVisible = panel.isVisible && !isClosing
        let pickerVisible = emojiPicker?.isVisible ?? false
        guard panelVisible || pickerVisible else { return }

        outsideClickReplayScheduled = true
        if pickerVisible {
            emojiPicker?.hide(animated: false)
        }

        let replayClick = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if NSApp.isActive {
                    NSApp.hide(nil)
                }
                if replay, AXIsProcessTrusted() {
                    self.postOutsideClick(at: location)
                }
                self.outsideClickReplayScheduled = false
            }
        }

        if panelVisible {
            hidePanel(restoreFocus: false, completion: replayClick)
        } else {
            replayClick()
        }
    }

    private func postOutsideClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: location,
            mouseButton: .left
        )
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        down?.post(tap: .cghidEventTap)
        usleep(25_000)
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: location,
            mouseButton: .left
        )
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.post(tap: .cghidEventTap)
        Log.debug("outside click replayed at \(location.x), \(location.y)")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(makeItem(title: "OPEN CSL", action: #selector(showFromMenu), key: ""))
        menu.addItem(makeEmojiPickerMenuItem())
        let clipboardItem = makeItem(
            title: "CLIPBOARD HISTORY…",
            action: #selector(openClipboardHistoryFromMenu),
            key: "v"
        )
        clipboardItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(clipboardItem)
        menu.addItem(makeItem(title: "EINSTELLUNGEN…", action: #selector(openSettingsFromMenu), key: ","))

        let bindings = hotkeyManager?.activeBindings.joined(separator: "  /  ") ?? "–"
        let info = makeItem(title: "HOTKEY  \(bindings)", action: nil, key: "")
        info.isEnabled = false
        menu.addItem(info)

        if spotlightShortcutEnabled == true {
            menu.addItem(makeItem(
                title: "SPOTLIGHT OCCUPIES CMD+SPACE…",
                action: #selector(openKeyboardSettings),
                key: ""
            ))
        }

        menu.addItem(.separator())

        let login = makeItem(title: "LAUNCH AT LOGIN", action: #selector(toggleLaunchAtLogin), key: "")
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(makeItem(title: "KEYBOARD SHORTCUTS…", action: #selector(openKeyboardSettings), key: ""))

        menu.addItem(.separator())
        menu.addItem(makeItem(title: "QUIT CSL", action: #selector(quit), key: ""))
    }

    private func makeEmojiPickerMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "CHARACTER PICKER", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(makeItem(title: "OPEN", action: #selector(showEmojiPickerFromMenu), key: ""))
        submenu.addItem(makeItem(title: "SETUP & PERMISSIONS…", action: #selector(showEmojiSetupFromMenu), key: ""))
        if let picker = emojiPicker {
            let fn = makeItem(title: "FN  \(picker.fnDetection)", action: nil, key: "")
            fn.isEnabled = false
            submenu.addItem(fn)
            let globe = makeItem(
                title: picker.systemGlobeKeyHandedOver ? "GLOBE KEY  READY" : "GLOBE KEY  SETUP NEEDED",
                action: nil,
                key: ""
            )
            globe.isEnabled = false
            submenu.addItem(globe)
        } else {
            let status = makeItem(title: "STARTING…", action: nil, key: "")
            status.isEnabled = false
            submenu.addItem(status)
        }
        root.submenu = submenu
        return root
    }

    @objc private func showEmojiPickerFromMenu() {
        emojiPicker?.show()
    }

    @objc private func showEmojiSetupFromMenu() {
        emojiPicker?.showSetup()
    }

    private func shouldStartEmojiPicker() -> Bool {
        let arguments = CommandLine.arguments
        if arguments.contains("--emoji-show") || arguments.contains("--emoji-snapshot")
            || arguments.contains("--emoji-setup") || arguments.contains("--emoji-setup-snapshot") {
            return true
        }
        if ProcessInfo.processInfo.environment["CSL_CLIPBOARD_SNAPSHOT"] != nil {
            return false
        }
        let testFlags = [
            "--snapshot", "--selftest", "--bench", "--index-folder",
            "--settings-snapshot", "--menu-test", "--drag-test",
            "--watch-test", "--watch-check", "--rank-test", "--fetch-icon"
        ]
        return !testFlags.contains { arguments.contains($0) }
    }

    private func startEmojiPicker() {
        guard emojiPicker == nil else { return }
        let picker = EmojiPickerFeature(brand: "CSL")
        picker.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            if visible, self.panel.isVisible {
                self.hidePanel(restoreFocus: false)
            }
            self.refreshOutsideClickTap()
        }
        emojiPicker = picker
        picker.start(showSetupIfNeeded: !CommandLine.arguments.contains("--emoji-no-setup"))
        handleEmojiTestArguments(picker)
    }

    private func handleEmojiTestArguments(_ picker: EmojiPickerFeature) {
        let arguments = CommandLine.arguments
        let query = argumentValue("--emoji-query")
        let category = argumentValue("--emoji-category")
        let skin = argumentValue("--emoji-skin").flatMap(Int.init)
        let show = { picker.show(query: query, category: category, skinTone: skin) }

        if arguments.contains("--emoji-show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: show)
        }
        if arguments.contains("--emoji-setup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                picker.showSetup()
            }
        }
        if let index = arguments.firstIndex(of: "--emoji-setup-snapshot"), index + 1 < arguments.count {
            let path = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                picker.showSetup()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    self?.writeSnapshot(window: picker.setupWindow, to: path)
                    NSApp.terminate(nil)
                }
            }
        }
        if let index = arguments.firstIndex(of: "--emoji-snapshot"), index + 1 < arguments.count {
            let path = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    self?.writeSnapshot(window: picker.panelWindow, to: path)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func argumentValue(_ flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private func makeItem(title: String, action: Selector?, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showFromMenu() {
        showPanel()
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }

    @objc private func openClipboardHistoryFromMenu() {
        showClipboardHistory()
    }

    private func showClipboardHistory() {
        // A command can request this while the launcher is already completing
        // its normal "launch" feedback. Entering clipboard mode takes over, so
        // cancel that completion instead of letting it close the panel.
        launchInProgress = false
        launchCompletionScheduled = false
        activeLaunchID = nil
        applicationWindowWaiter.cancel()
        SettingsWindowController.shared.close(restoreFocus: false)
        if !panel.isVisible {
            showPanel()
        }
        viewController.enterClipboardMode()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Best effort: symbolic hotkey 64 is "Show Spotlight search". When the key
    /// is absent from the plist, the system default (enabled) applies.
    private var spotlightShortcutEnabled: Bool? {
        guard let hotkeys = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] else { return nil }

        if let entry = hotkeys["64"] as? [String: Any],
           let enabled = entry["enabled"] as? Bool {
            return enabled
        }
        return true
    }

    private var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.debug("login item failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "LAUNCH AT LOGIN"
            alert.informativeText = """
            macOS konnte CSL nicht als Login-Objekt eintragen.
            Lege CSL.app in /Applications ab und versuche es erneut.
            """
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Search engine

    func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool) {
        viewController?.apply(results: results, isSearching: isSearching)

        guard selftestTerm != nil, selftestStarted > 0 else { return }

        if !didLogSelftestFirstUpdate {
            didLogSelftestFirstUpdate = true
            let elapsed = (CACurrentMediaTime() - selftestStarted) * 1000
            Log.always(String(format: "first update after %.1f ms (searching: %@)", elapsed, isSearching ? "yes" : "no"))
        }

        Log.always("— \(results.count) results, searching=\(isSearching)")
        for result in results.prefix(12) {
            Log.always(String(format: "   %4d  %@  [%@]", result.score, result.title, result.subtitle))
        }
    }

    // MARK: - Debug / testing entry points

    private func parseArguments() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            snapshotPath = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--query"), index + 1 < arguments.count {
            queryArgument = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--selftest"), index + 1 < arguments.count {
            selftestTerm = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--bench"), index + 1 < arguments.count {
            benchTerms = arguments[index + 1]
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if let index = arguments.firstIndex(of: "--index-folder"), index + 1 < arguments.count {
            indexTestFolder = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--fetch-icon"), index + 1 < arguments.count {
            iconTestURL = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--settings-snapshot"), index + 1 < arguments.count {
            settingsSnapshotPath = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count {
            settingsTabArgument = arguments[index + 1]
        }
        settingsAtLaunch = arguments.contains("--settings")
        reindexAtLaunch = arguments.contains("--reindex")
        menuTest = arguments.contains("--menu-test")
        dragTest = arguments.contains("--drag-test")
        if let index = arguments.firstIndex(of: "--watch-test"), index + 1 < arguments.count {
            watchTestFolder = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--watch-check"), index + 1 < arguments.count {
            watchCheckFolder = arguments[index + 1]
        }
        if let index = arguments.firstIndex(of: "--scale"), index + 1 < arguments.count,
           let value = Double(arguments[index + 1]) {
            scaleArgument = CGFloat(value)
        }
        rankTest = arguments.contains("--rank-test")
        if let index = arguments.firstIndex(of: "--snapshot-delay"),
           index + 1 < arguments.count,
           let value = TimeInterval(arguments[index + 1]) {
            snapshotDelay = max(0.05, value)
        }
    }

    private func runSnapshot() {
        guard let path = snapshotPath else { return }
        showPanel()
        if let queryArgument, !queryArgument.isEmpty {
            viewController.setSearchText(queryArgument)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.writeSnapshot(to: path)
            NSApp.terminate(nil)
        }
    }

    private func writeSnapshot(to path: String) {
        writeSnapshot(window: panel, to: path)
    }

    private func writeSnapshot(window: NSWindow?, to path: String) {
        guard let contentView = window?.contentView else {
            Log.always("snapshot failed: no window")
            return
        }
        contentView.layoutSubtreeIfNeeded()

        guard let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            Log.always("snapshot failed: no bitmap rep")
            return
        }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)

        if let data = representation.representation(using: .png, properties: [:]) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
                Log.always("snapshot written: \(path)")
            } catch {
                Log.always("snapshot write failed: \(error)")
            }
        }
    }

    private func runBench() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.runBenchTerm(at: 0)
        }
    }

    private func runBenchTerm(at index: Int) {
        guard index < benchTerms.count else {
            Log.always("bench done")
            NSApp.terminate(nil)
            return
        }

        let term = benchTerms[index]
        Log.always("BENCH \"\(term)\"")
        engine.search(term)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.runBenchTerm(at: index + 1)
        }
    }

    private func runWatchCheck() {
        FileIndex.shared.loadAsync { [weak self] in
            FileWatcher.shared.sync()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                guard let self else { return }
                let term = self.queryArgument ?? "resume"
                let found = FileIndex.shared.results(for: term).map(\.title)
                Log.always("resume check: \(found)")
                NSApp.terminate(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            Log.always("resume check timeout")
            NSApp.terminate(nil)
        }
    }

    private func runWatchTest(_ folder: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = SettingsStore.normalizeFolder(folder)
        SettingsStore.shared.addIndexedFolder(path)
        Log.always("WATCH TEST \(path)")

        FileIndex.shared.loadAsync {
            FileIndex.shared.commit(root: path, entries: [], lastEventID: nil) {
                FileWatcher.shared.sync()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    self.watchTestCreateFile(in: path)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 45) {
            Log.always("watch test timeout")
            NSApp.terminate(nil)
        }
    }

    private func watchTestCreateFile(in path: String) {
        let file = path + "/brandneu-xyz.txt"
        FileManager.default.createFile(atPath: file, contents: Data("hello".utf8))
        Log.always("created \(file)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            let found = FileIndex.shared.results(for: "brandneu").map(\.title)
            Log.always("after create: \(found)")

            let directory = path + "/ordner-a"
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: directory + "/innen.txt", contents: Data("inside".utf8))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                let inside = FileIndex.shared.results(for: "innen").map(\.title)
                Log.always("after mkdir: \(inside)")

                try? FileManager.default.moveItem(atPath: directory, toPath: path + "/ordner-b")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    let renamed = FileIndex.shared.results(for: "innen").map(\.subtitle)
                    Log.always("after dir rename: \(renamed)")

                    try? FileManager.default.moveItem(atPath: file, toPath: path + "/umbenannt-xyz.txt")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                        let newName = FileIndex.shared.results(for: "umbenannt").map(\.title)
                        let oldName = FileIndex.shared.results(for: "brandneu").map(\.title)
                        Log.always("after file rename: new=\(newName) old=\(oldName)")

                        try? FileManager.default.removeItem(atPath: path + "/umbenannt-xyz.txt")
                        try? FileManager.default.removeItem(atPath: path + "/ordner-b")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            Log.always("after delete: total=\(FileIndex.shared.totalCount)")
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
        }
    }

    private func runRankTest() {
        guard let dataDir = ProcessInfo.processInfo.environment["CSL_DATA_DIR"],
              !dataDir.isEmpty else {
            Log.always("rank test requires CSL_DATA_DIR")
            NSApp.terminate(nil)
            return
        }

        ResultRanker.shared.loadAsync {
            ResultRanker.shared.reset()

            func make(_ id: String, _ title: String, _ kind: ResultKind, _ score: Int) -> SearchResult {
                SearchResult(
                    id: id,
                    title: title,
                    subtitle: "TEST",
                    kind: kind,
                    icon: .glyph(.gear),
                    score: score,
                    titleMatch: [],
                    action: .open(URL(fileURLWithPath: "/tmp/" + title))
                )
            }

            let app = make("app:/Applications/Designer.app", "Designer", .application, 1060)
            let website = make("web:design", "Design", .website, 1000)
            let fileA = make("file:/tmp/design-spec.pdf", "design-spec.pdf", .file, 920)
            let fileB = make("file:/tmp/design-notes.txt", "design-notes.txt", .file, 920)

            for _ in 0..<8 {
                ResultRanker.shared.record(fileB, query: "design", revealed: false)
            }

            let design = ResultRanker.shared.ranked([app, website, fileA, fileB], query: "design")
            Log.always("RANK TEST design: " + design.map { "\($0.title)=\($0.score)" }.joined(separator: " | "))

            let command = make("cmd:screenshot", "SCREENSHOT", .command, 960)
            for _ in 0..<100 {
                ResultRanker.shared.record(command, query: "screenshot", revealed: false)
            }
            let shot = ResultRanker.shared.ranked([command], query: "screenshot")
            Log.always("RANK TEST command: " + shot.map { "\($0.title)=\($0.score)" }.joined(separator: " | "))

            ResultRanker.shared.flush()
            NSApp.terminate(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            Log.always("rank test timeout")
            NSApp.terminate(nil)
        }
    }

    private func runContextTest() {
        showPanel()
        let term = queryArgument ?? "safari"
        viewController.setSearchText(term)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let titles = self.viewController.debugContextMenuTitles(for: 0)
            Log.always("context menu: \(titles.joined(separator: " | "))")
            if self.dragTest {
                Log.always("drag item: \(self.viewController.debugDragDescription(for: 0))")
            }
            NSApp.terminate(nil)
        }
    }

    private func runIndexTest(_ folder: String) {
        let path = SettingsStore.normalizeFolder(folder)
        Log.always("INDEX TEST \(path)")
        SettingsStore.shared.addIndexedFolder(path)

        FileIndex.shared.loadAsync {
            var lastPrint: CFTimeInterval = 0
            let center = NotificationCenter.default

            center.addObserver(
                forName: .cslIndexProgress,
                object: nil,
                queue: .main
            ) { note in
                guard let progress = note.userInfo?["progress"] as? FolderIndexer.Progress else { return }
                let now = CACurrentMediaTime()
                let isFinal = progress.phase == .indexing && progress.processed == progress.total
                guard now - lastPrint > 0.4 || isFinal || progress.phase != .indexing else { return }
                lastPrint = now
                let eta = progress.eta.map { String(format: "%.1fs", $0) } ?? "—"
                Log.always(String(
                    format: "%@ %5.1f%%  %d/%d  eta=%@  %@",
                    progress.phase.rawValue,
                    progress.fraction * 100,
                    progress.processed,
                    progress.total,
                    eta,
                    progress.currentItem ?? ""
                ))
            }

            center.addObserver(
                forName: .cslIndexStateChanged,
                object: nil,
                queue: .main
            ) { note in
                guard let isIndexing = note.userInfo?["isIndexing"] as? Bool, !isIndexing else { return }

                let start = CACurrentMediaTime()
                let results = FileIndex.shared.results(for: "test", limit: 10)
                let elapsed = (CACurrentMediaTime() - start) * 1000
                Log.always(String(
                    format: "index done: %d entries, %d roots, search 'test' -> %d in %.1f ms",
                    FileIndex.shared.totalCount,
                    FileIndex.shared.roots.count,
                    results.count,
                    elapsed
                ))
                for result in results.prefix(5) {
                    Log.always("  \(result.title)  [\(result.subtitle)]")
                }
                NSApp.terminate(nil)
            }

            IndexCoordinator.shared.index(folder: path)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
            Log.always("index test timeout")
            NSApp.terminate(nil)
        }
    }

    private func runIconTest(_ rawURL: String) {
        Log.always("ICON TEST \(rawURL)")
        let center = NotificationCenter.default

        center.addObserver(
            forName: .cslWebsiteIconUpdated,
            object: nil,
            queue: .main
        ) { note in
            guard let success = note.userInfo?["success"] as? Bool else { return }
            if let id = note.userInfo?["id"] as? UUID,
               let site = SettingsStore.shared.website(id: id) {
                let path = FaviconService.shared.iconURL(for: site)?.path ?? "none"
                Log.always("icon success=\(success) title=\(site.displayTitle) path=\(path)")
            }
            NSApp.terminate(nil)
        }

        guard SettingsStore.shared.addWebsite(rawURL: rawURL, title: "") != nil else {
            Log.always("could not parse url")
            NSApp.terminate(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            Log.always("icon test timeout")
            NSApp.terminate(nil)
        }
    }

    private func runSelfTest(_ term: String) {
        Log.always("CSL SELFTEST \"\(term)\"")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.selftestStarted = CACurrentMediaTime()
            self.didLogSelftestFirstUpdate = false
            self.engine.search(term)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                Log.always("done")
                NSApp.terminate(nil)
            }
        }
    }
}
