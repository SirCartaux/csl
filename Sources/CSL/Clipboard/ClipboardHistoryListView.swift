import AppKit

/// Clipboard history embedded in the launcher. It deliberately has no header
/// or window chrome of its own; the launcher's field filters it and the shared
/// footer switches to clipboard hints.
final class ClipboardHistoryListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let store = ClipboardHistoryStore.shared
    private let scrollView = NSScrollView()
    private let tableView = ClipboardHistoryTableView()
    private var entries: [ClipboardEntry] = []
    private var selectedIndex = 0
    private var query = ""
    private var contextEntryID: UUID?

    var onChange: ((Int, Int) -> Void)?
    var onCopy: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowHeight = 68
        tableView.usesAutomaticRowHeights = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        if #available(macOS 11.0, *) { tableView.style = .plain }
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onDoubleClick = { [weak self] row in
            guard let self, self.entries.indices.contains(row) else { return }
            self.selectedIndex = row
            if self.store.copy(self.entries[row]) {
                self.onCopy?()
            }
        }
        tableView.menuProvider = { [weak self] row in
            self?.contextMenu(for: row)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard-entry"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        addSubview(scrollView)

        NotificationCenter.default.addObserver(
            forName: .cslClipboardChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    // MARK: - Presentation

    func filter(_ query: String) {
        self.query = query
        reload(preserveSelection: false)
    }

    func reload(preserveSelection: Bool = true) {
        let previousID = preserveSelection && entries.indices.contains(selectedIndex)
            ? entries[selectedIndex].id
            : nil
        entries = store.filtered(query)
        if let previousID, let index = entries.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        selectedIndex = min(max(selectedIndex, 0), max(0, entries.count - 1))

        needsLayout = true
        layoutSubtreeIfNeeded()
        tableView.reloadData()
        if !entries.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
            tableView.scrollRowToVisible(selectedIndex)
        } else {
            tableView.deselectAll(nil)
        }
        onChange?(entries.count, store.totalBytes)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        if let column = tableView.tableColumns.first {
            column.width = max(1, bounds.width - 8)
        }
        tableView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(1, bounds.width - 8),
            height: max(bounds.height, CGFloat(entries.count) * tableView.rowHeight)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.fill(bounds, Theme.bg)
        guard entries.isEmpty else { return }

        let title: String
        let subtitle: String
        if store.entries.isEmpty {
            title = "CLIPBOARD IS EMPTY"
            subtitle = "COPY TEXT, IMAGES OR FILES"
        } else {
            title = "NO MATCHES"
            subtitle = "TRY A DIFFERENT FILTER"
        }

        let glyph = PixelGlyph.clipboard.image(size: 28, color: Theme.textFaint.withAlphaComponent(0.55))
        glyph.draw(in: CGRect(x: bounds.midX - 14, y: bounds.midY - 42, width: 28, height: 28))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (title as NSString).draw(
            in: CGRect(x: 0, y: bounds.midY + 2, width: bounds.width, height: 18),
            withAttributes: [
                .font: Theme.launcherDisplayBold(11),
                .foregroundColor: Theme.textDim,
                .paragraphStyle: paragraph
            ]
        )
        (subtitle as NSString).draw(
            in: CGRect(x: 0, y: bounds.midY + 24, width: bounds.width, height: 12),
            withAttributes: [
                .font: Theme.launcherDisplay(8),
                .foregroundColor: Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
    }

    // MARK: - Selection/actions

    var selectedEntry: ClipboardEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        select(selectedIndex + delta)
    }

    private func select(_ index: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = min(max(index, 0), entries.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
        refreshSelection()
    }

    @discardableResult
    func copySelected() -> Bool {
        guard let entry = selectedEntry else { return false }
        guard store.copy(entry) else {
            NSSound.beep()
            return false
        }
        onCopy?()
        return true
    }

    func pinSelected() {
        guard let entry = selectedEntry else { return }
        store.togglePin(entry.id)
    }

    func deleteSelected() {
        guard let entry = selectedEntry else { return }
        store.delete(entry.id)
    }

    func clearAll() {
        guard !store.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "CLEAR CLIPBOARD HISTORY?"
        alert.informativeText = "This removes all \(store.entries.count) saved items, including pinned ones."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "CLEAR")
        alert.addButton(withTitle: "CANCEL")
        if alert.runModal() == .alertFirstButtonReturn {
            store.clear()
        }
    }

    private func refreshSelection() {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.location != NSNotFound else { return }
        for row in visible.location..<min(NSMaxRange(visible), entries.count) {
            (tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? ClipboardEntryRowView)?.configure(
                    with: entries[row],
                    selected: row == selectedIndex,
                    thumbnail: store.image(for: entries[row])
                )
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let view = tableView.makeView(withIdentifier: ClipboardEntryRowView.identifier, owner: nil)
            as? ClipboardEntryRowView ?? ClipboardEntryRowView()
        view.identifier = ClipboardEntryRowView.identifier
        view.configure(
            with: entries[row],
            selected: row == selectedIndex,
            thumbnail: store.image(for: entries[row])
        )
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard entries.indices.contains(row) else { return }
        selectedIndex = row
        refreshSelection()
    }

    // MARK: - Context menu

    private func contextMenu(for row: Int) -> NSMenu? {
        guard entries.indices.contains(row) else { return nil }
        selectedIndex = row
        contextEntryID = entries[row].id
        let entry = entries[row]
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
        guard let entry = contextEntry, store.copy(entry) else { return }
        onCopy?()
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
}


final class ClipboardHistoryTableView: NSTableView {
    var onDoubleClick: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        if event.clickCount == 2, row >= 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onDoubleClick?(row)
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return menuProvider?(row)
    }
}
