import AppKit

final class ClipboardHistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = ClipboardHistoryWindowController()

    private let window = ClipboardHistoryWindow()
    private let root = ClipboardHistoryRootView(frame: .zero)
    var nsWindow: NSWindow { window }
    var isVisible: Bool { isShown }
    private let store = ClipboardHistoryStore.shared
    private var filtered: [ClipboardEntry] = []
    private var selectedIndex = 0
    private var keyMonitor: Any?
    private var isShown = false
    private var contextEntryID: UUID?

    private override init() {
        super.init()
        window.contentView = root
        window.setContentSize(ClipboardHistoryLayout.windowSize)

        root.tableView.dataSource = self
        root.tableView.delegate = self
        root.tableView.onDoubleClick = { [weak self] row in
            self?.copyRow(row)
        }
        root.tableView.menuProvider = { [weak self] row in
            self?.contextMenu(for: row)
        }
        root.onFilter = { [weak self] in self?.reload() }
        root.onSubmit = { [weak self] in _ = self?.copySelected() }
        root.onClose = { [weak self] in self?.close() }
        root.onClear = { [weak self] in self?.confirmClear() }

        NotificationCenter.default.addObserver(
            forName: .cslClipboardChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isShown else { return }
            self.reload()
        }
    }

    // MARK: - Showing

    func show() {
        store.start()
        if isShown {
            reload()
            window.makeKeyAndOrderFront(nil)
            root.focusSearch()
            return
        }

        isShown = true
        reload()
        positionWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        root.startGlow()
        installKeyMonitor()
        root.focusSearch()
        Log.debug("clipboard history shown")
    }

    func close(restoreFocus: Bool = true) {
        guard isShown else { return }
        isShown = false
        root.stopGlow()
        window.orderOut(nil)
        removeKeyMonitor()
        if restoreFocus, NSApp.isActive {
            NSApp.hide(nil)
        }
        Log.debug("clipboard history closed")
    }

    private func positionWindow() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: floor(visible.midX - size.width / 2),
            y: floor(visible.midY - size.height / 2 + 20)
        ))
    }

    // MARK: - Data

    private func reload() {
        let query = root.searchField.stringValue
        let previousID = filtered.indices.contains(selectedIndex) ? filtered[selectedIndex].id : nil
        filtered = store.filtered(query)
        if let previousID, let index = filtered.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        selectedIndex = min(max(selectedIndex, 0), max(0, filtered.count - 1))

        root.usedBytes = store.totalBytes
        root.itemCount = filtered.count
        root.storeEmpty = store.entries.isEmpty
        root.isFiltering = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        root.needsDisplay = true

        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        root.tableView.reloadData()
        if !filtered.isEmpty {
            root.tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            root.tableView.scrollRowToVisible(selectedIndex)
        } else {
            root.tableView.deselectAll(nil)
        }
    }

    private func refreshSelection() {
        let visible = root.tableView.rows(in: root.tableView.visibleRect)
        guard visible.location != NSNotFound else { return }
        for row in visible.location..<min(NSMaxRange(visible), filtered.count) {
            (root.tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? ClipboardEntryRowView)?.configure(
                    with: filtered[row],
                    selected: row == selectedIndex,
                    thumbnail: store.image(for: filtered[row])
                )
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let view = tableView.makeView(withIdentifier: ClipboardEntryRowView.identifier, owner: nil)
            as? ClipboardEntryRowView ?? ClipboardEntryRowView()
        view.identifier = ClipboardEntryRowView.identifier
        view.configure(
            with: filtered[row],
            selected: row == selectedIndex,
            thumbnail: store.image(for: filtered[row])
        )
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = root.tableView.selectedRow
        guard filtered.indices.contains(row) else { return }
        selectedIndex = row
        refreshSelection()
    }

    // MARK: - Actions

    private func select(_ index: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = min(max(index, 0), filtered.count - 1)
        root.tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        root.tableView.scrollRowToVisible(selectedIndex)
        refreshSelection()
    }

    @discardableResult
    private func copySelected() -> Bool {
        guard filtered.indices.contains(selectedIndex) else { return false }
        return copyRow(selectedIndex)
    }

    @discardableResult
    private func copyRow(_ row: Int) -> Bool {
        guard filtered.indices.contains(row) else { return false }
        let entry = filtered[row]
        let copied = store.copy(entry)
        if copied {
            close(restoreFocus: true)
        } else {
            NSSound.beep()
        }
        return copied
    }

    private func pinSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        store.togglePin(filtered[selectedIndex].id)
    }

    private func deleteSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        let id = filtered[selectedIndex].id
        store.delete(id)
    }

    private func confirmClear() {
        guard !store.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "CLEAR CLIPBOARD HISTORY?"
        alert.informativeText = "This removes all \(store.entries.count) saved items. Pinned items are removed too."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "CLEAR")
        alert.addButton(withTitle: "CANCEL")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
            root.focusSearch()
        }
    }

    // MARK: - Context menu

    private func contextMenu(for row: Int) -> NSMenu? {
        guard filtered.indices.contains(row) else { return nil }
        selectedIndex = row
        contextEntryID = filtered[row].id
        let entry = filtered[row]
        let menu = NSMenu()
        menu.autoenablesItems = false

        let copy = NSMenuItem(title: "COPY", action: #selector(contextCopy), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)

        let pin = NSMenuItem(
            title: entry.pinned ? "UNPIN" : "PIN",
            action: #selector(contextPin),
            keyEquivalent: ""
        )
        pin.target = self
        menu.addItem(pin)

        let delete = NSMenuItem(title: "DELETE", action: #selector(contextDelete), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)

        if entry.kind == .files {
            menu.addItem(.separator())
            let reveal = NSMenuItem(title: "SHOW IN FINDER", action: #selector(contextReveal), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)
        }
        return menu
    }

    private var contextEntry: ClipboardEntry? {
        guard let id = contextEntryID else { return nil }
        return store.entries.first { $0.id == id }
    }

    @objc private func contextCopy() {
        guard let entry = contextEntry else { return }
        if store.copy(entry) {
            close(restoreFocus: true)
        }
    }

    @objc private func contextPin() {
        guard let entry = contextEntry else { return }
        store.togglePin(entry.id)
    }

    @objc private func contextDelete() {
        guard let entry = contextEntry else { return }
        store.delete(entry.id)
    }

    @objc private func contextReveal() {
        guard let entry = contextEntry,
              let paths = entry.filePaths,
              !paths.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isKeyWindow else { return event }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])

            if event.keyCode == 53 {
                self.close()
                return nil
            }
            if event.keyCode == 126 {
                self.select(self.selectedIndex - 1)
                return nil
            }
            if event.keyCode == 125 {
                self.select(self.selectedIndex + 1)
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                _ = self.copySelected()
                return nil
            }
            if event.keyCode == 35, flags.contains(.command) {
                self.pinSelected()
                return nil
            }
            if event.keyCode == 51, flags.contains(.command) {
                if flags.contains(.shift) {
                    self.confirmClear()
                } else {
                    self.deleteSelected()
                }
                return nil
            }
            if event.keyCode == 13, flags.contains(.command) {
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
