import AppKit

enum SettingsTab: String, CaseIterable {
    case folders
    case ignore
    case websites
    case animation
    case general

    var title: String {
        switch self {
        case .folders: return "ORDNER"
        case .ignore: return "IGNORIEREN"
        case .websites: return "WEBSITES"
        case .animation: return "ANIMATION"
        case .general: return "ALLGEMEIN"
        }
    }
}

final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private let window: SettingsWindow
    private let rootView = SettingsRootView()
    private var sections: [SettingsTab: SettingsSection] = [:]
    private var currentTab: SettingsTab = .folders
    private var keyMonitor: Any?
    private var isShown = false

    var nsWindow: NSWindow { window }
    var currentSection: SettingsSection? { sections[currentTab] }
    var isVisible: Bool { isShown }

    func focusWebsiteURLField() {
        (sections[.websites] as? WebsitesSection)?.focusURLField()
    }

    private override init() {
        window = SettingsWindow()
        super.init()

        window.contentView = rootView
        window.setContentSize(SettingsLayout.windowSize)

        rootView.sidebar.onSelect = { [weak self] index in
            guard let self else { return }
            let tabs = SettingsTab.allCases
            guard tabs.indices.contains(index) else { return }
            self.select(tabs[index])
        }
        rootView.onClose = { [weak self] in
            self?.close()
        }
        NotificationCenter.default.addObserver(
            forName: .cslIndexProgress,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let progress = note.userInfo?["progress"] as? FolderIndexer.Progress else { return }
            self.sections.values.forEach { $0.updateIndexProgress(progress) }
        }

        for name in [Notification.Name.cslSettingsChanged,
                     .cslIndexFinished,
                     .cslIndexLoaded,
                     .cslIndexChanged,
                     .cslIndexStateChanged,
                     .cslWebsiteIconUpdated] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.sections.values.forEach { $0.reload() }
            }
        }
    }

    // MARK: - Showing

    func show(tab: SettingsTab? = nil) {
        if let tab { currentTab = tab }
        if isShown {
            if let tab { select(tab) }
            window.makeKeyAndOrderFront(nil)
            return
        }

        isShown = true
        select(currentTab)
        positionWindow()
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        rootView.startGlow()
        installKeyMonitor()
        Log.debug("settings shown")
    }

    func close(restoreFocus: Bool = true) {
        guard isShown else { return }
        isShown = false
        rootView.stopGlow()
        window.orderOut(nil)
        removeKeyMonitor()
        if restoreFocus, NSApp.isActive {
            NSApp.hide(nil)
        }
        Log.debug("settings closed")
    }

    private func positionWindow() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: floor(visible.midX - size.width / 2),
            y: floor(visible.midY - size.height / 2 + 24)
        )
        window.setFrameOrigin(origin)
    }

    // MARK: - Tabs

    private func select(_ tab: SettingsTab) {
        guard let index = SettingsTab.allCases.firstIndex(of: tab) else { return }
        currentTab = tab
        rootView.sidebar.selectedIndex = index

        if let existing = sections[tab] {
            contentView(section: existing)
            existing.reload()
            return
        }

        let section: SettingsSection
        switch tab {
        case .folders:
            section = FoldersSection(frame: rootView.contentContainer.bounds)
        case .ignore:
            section = IgnoreSection(frame: rootView.contentContainer.bounds)
        case .websites:
            section = WebsitesSection(frame: rootView.contentContainer.bounds)
        case .animation:
            section = AnimationSection(frame: rootView.contentContainer.bounds)
        case .general:
            section = GeneralSection(frame: rootView.contentContainer.bounds)
        }
        sections[tab] = section
        contentView(section: section)
        section.reload()
    }

    private func contentView(section: SettingsSection) {
        for subview in rootView.contentContainer.subviews {
            subview.removeFromSuperview()
        }
        section.frame = rootView.contentContainer.bounds
        section.autoresizingMask = [.width, .height]
        rootView.contentContainer.addSubview(section)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow else { return event }
            if event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.keyCode == 13, event.modifierFlags.contains(.command) {
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
