import AppKit
import QuickLookUI

final class SearchViewController: NSViewController {
    var engine: SearchEngine?

    var onClose: (() -> Void)?
    var onChoose: ((SearchResult, Bool) -> Void)?
    var onDragOut: ((SearchResult) -> Void)?

    let searchField = PixelTextField(frame: .zero)

    private let rootView = RootView()
    private let scrollView = NSScrollView()
    private let tableView = ResultTableView()
    private let glowView = GlowView(frame: .zero)
    private let resizeHandle = ResizeHandleView()

    private var results: [SearchResult] = []
    private var selectedIndex = 0
    private var resetSelectionOnNextUpdate = false
    private var userNavigated = false
    private var suppressClick = false
    private(set) var isDraggingResult = false
    private var contextResultID: String?
    private var statusWorkItem: DispatchWorkItem?
    private var isNavigatingResults = false
    private var previewURL: URL?
    private var previewIsOpen = false
    private var quickLookMonitor: Any?
    private var draggedResult: SearchResult?

    var isPreviewing: Bool { previewIsOpen }

    func dismissQuickLook() {
        guard previewIsOpen else { return }
        closeQuickLook(restoreFocus: false)
    }

    deinit {
        if let quickLookMonitor {
            NSEvent.removeMonitor(quickLookMonitor)
        }
    }

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildField()
        buildList()
        rootView.onOutsideClick = { [weak self] in
            self?.onClose?()
        }
        rootView.addSubview(scrollView)
        rootView.addSubview(searchField)
        rootView.addSubview(glowView)

        resizeHandle.frame = rootView.bounds
        resizeHandle.autoresizingMask = [.width, .height]
        resizeHandle.onScaleChanged = { [weak self] scale in
            self?.applyLauncherScale(scale)
        }
        resizeHandle.onScaleCommitted = { [weak self] in
            self?.persistLauncherScale()
            self?.focus()
        }
        rootView.addSubview(resizeHandle, positioned: .above, relativeTo: glowView)

        searchField.applyLauncherScale()
        glowView.scale = Theme.launcherScale
        installQuickLookMonitor()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let bounds = view.bounds
        let panel = Layout.panelRect(in: bounds)
        let listRect = Layout.listRect(in: bounds)
        let fieldRect = Layout.fieldRect(in: bounds)

        glowView.frame = view.bounds
        resizeHandle.frame = view.bounds
        scrollView.frame = listRect
        searchField.frame = CGRect(
            x: panel.minX + Theme.ls(44),
            y: fieldRect.minY + Theme.ls(12),
            width: max(80, panel.width - Theme.ls(44) - Theme.ls(18)),
            height: Theme.ls(30)
        )

        if let column = tableView.tableColumns.first {
            column.width = listRect.width
        }
        resizeTable()
        view.window?.invalidateCursorRects(for: resizeHandle)
    }

    /// Reflows the launcher for a new global scale. The actual window frame is
    /// changed by the resize handle, which keeps the panel centered.
    func applyLauncherScale(_ scale: CGFloat) {
        let clamped = min(max(scale, Theme.minLauncherScale), Theme.maxLauncherScale)
        guard abs(clamped - Theme.launcherScale) > 0.0001 else { return }

        Theme.launcherScale = clamped
        searchField.applyLauncherScale()
        glowView.scale = clamped
        tableView.rowHeight = Theme.rowHeight
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        resizeTable()
        tableView.reloadData()
        rootView.needsDisplay = true
        glowView.needsDisplay = true
        tableView.needsDisplay = true
        resizeHandle.window?.invalidateCursorRects(for: resizeHandle)
    }

    private func persistLauncherScale() {
        SettingsStore.shared.setLauncherScale(Double(Theme.launcherScale))
    }

    private func resizeTable() {
        let listRect = Layout.listRect(in: view.bounds)
        let needed = CGFloat(results.count) * Theme.rowHeight
        tableView.frame = CGRect(
            x: 0,
            y: 0,
            width: listRect.width,
            height: max(listRect.height, needed)
        )
    }

    // MARK: - Setup

    private func buildField() {
        searchField.delegate = self
        searchField.setAccessibilityLabel("Search")
        searchField.onMouseDown = { [weak self] in
            self?.isNavigatingResults = false
        }
    }

    private func buildList() {
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowHeight = Theme.rowHeight
        tableView.usesAutomaticRowHeights = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.onDoubleClick = { [weak self] row in
            self?.openResult(at: row)
        }
        tableView.onMouseDown = { [weak self] in
            self?.suppressClick = false
        }
        tableView.contextMenuProvider = { [weak self] row in
            self?.makeContextMenu(for: row)
        }
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: true)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    // MARK: - Presentation

    func prepareForPresentation() {
        clearStatus()
        isNavigatingResults = false
        if previewIsOpen {
            closeQuickLook(restoreFocus: false)
        }
        searchField.stringValue = ""
        resetSelectionOnNextUpdate = true
        userNavigated = false
        results = []
        selectedIndex = 0
        rootView.query = ""
        rootView.resultCount = 0
        rootView.isSearching = false
        tableView.reloadData()
        engine?.search("")
        refreshWindowSize()
    }

    func startGlow() {
        glowView.startPulse()
    }

    func stopGlow() {
        glowView.stopPulse()
    }

    func focus() {
        view.window?.makeFirstResponder(searchField)
        searchField.styleEditor()
        if let editor = searchField.currentEditor() as? NSTextView {
            let end = (searchField.stringValue as NSString).length
            editor.selectedRange = NSRange(location: end, length: 0)
        }
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: searchField))
        if let editor = searchField.currentEditor() as? NSTextView {
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
    }

    var preferredContentHeight: CGFloat {
        Theme.headerHeight + Theme.fieldHeight + Theme.footerHeight + listHeight
    }

    private var listHeight: CGFloat {
        guard !results.isEmpty else { return Theme.emptyListHeight }
        let rows = min(results.count, Theme.maxRows)
        return max(Theme.emptyListHeight, CGFloat(rows) * Theme.rowHeight)
    }

    private func refreshWindowSize() {
        guard let window = view.window else { return }

        let height = preferredContentHeight + 2 * Theme.panelInset
        let width = Theme.panelWidth + 2 * Theme.panelInset
        guard abs(window.frame.height - height) > 0.5 || abs(window.frame.width - width) > 0.5 else {
            return
        }

        var frame = window.frame
        // Keep the top edge fixed while the list grows/shrinks.
        frame.origin.y += frame.height - height
        frame.size = NSSize(width: width, height: height)
        if let screen = window.screen {
            let visible = screen.visibleFrame
            let margin: CGFloat = 8
            frame.origin.x = min(max(frame.minX, visible.minX + margin), visible.maxX - margin - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY + margin), visible.maxY - margin - frame.height)
        }
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Results

    func apply(results: [SearchResult], isSearching: Bool) {
        let previousID: String? = self.results.indices.contains(selectedIndex)
            ? self.results[selectedIndex].id
            : nil

        self.results = results

        if resetSelectionOnNextUpdate {
            selectedIndex = 0
            resetSelectionOnNextUpdate = false
        } else if userNavigated, let previousID,
                  let index = results.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
        if results.isEmpty {
            selectedIndex = 0
            isNavigatingResults = false
        }

        resizeTable()
        tableView.reloadData()
        if !results.isEmpty {
            tableView.scrollRowToVisible(selectedIndex)
        }

        rootView.query = searchField.stringValue
        rootView.resultCount = results.count
        rootView.isSearching = isSearching
        rootView.needsDisplay = true
        refreshWindowSize()
    }

    // MARK: - Selection

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = max(0, min(results.count - 1, selectedIndex + delta))
        guard next != selectedIndex else { return }
        userNavigated = true
        isNavigatingResults = true
        selectedIndex = next
        tableView.reloadData()
        tableView.scrollRowToVisible(selectedIndex)
    }

    private func chooseSelected(reveal: Bool) {
        guard results.indices.contains(selectedIndex) else { return }
        Log.debug("open result: \(results[selectedIndex].title)")
        onChoose?(results[selectedIndex], reveal)
    }

    @objc private func rowClicked() {
        guard !suppressClick else { return }
        let row = tableView.clickedRow
        guard results.indices.contains(row) else { return }
        selectedIndex = row
        userNavigated = true
        isNavigatingResults = true
        tableView.reloadData()
        focus()
        tableView.scrollRowToVisible(row)
        Log.debug("row selected: \(row)")
    }

    private func openResult(at row: Int) {
        guard results.indices.contains(row) else { return }
        selectedIndex = row
        tableView.reloadData()
        Log.debug("row double-clicked: \(row)")
        chooseSelected(reveal: NSEvent.modifierFlags.contains(.command))
    }

    private func beginResultsNavigation() {
        guard !results.isEmpty else { return }
        isNavigatingResults = true
        selectedIndex = 0
        tableView.reloadData()
        tableView.scrollRowToVisible(0)
    }

    // MARK: - Quick Look

    private func selectedFileURL() -> URL? {
        guard results.indices.contains(selectedIndex) else { return nil }
        let result = results[selectedIndex]
        switch result.kind {
        case .file:
            break
        default:
            return nil
        }
        switch result.action {
        case .open(let url), .reveal(let url):
            return url.isFileURL ? url : nil
        case .run:
            return nil
        }
    }

    private func installQuickLookMonitor() {
        guard quickLookMonitor == nil else { return }
        quickLookMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if previewIsOpen, QLPreviewPanel.sharedPreviewPanelExists() {
                if event.isARepeat { return nil }
                switch event.keyCode {
                case 49, 53: // Space, Escape
                    self.closeQuickLook(restoreFocus: true)
                    return nil
                case 36, 76: // Return, keypad Enter
                    self.closeQuickLook(restoreFocus: false)
                    self.chooseSelected(reveal: event.modifierFlags.contains(.command))
                    return nil
                default:
                    break
                }

                let modifiers = event.modifierFlags.intersection([.command, .control, .option])
                if modifiers.isEmpty {
                    if event.keyCode == 51 || event.keyCode == 117 { // Backspace, forward delete
                        self.closeQuickLook(restoreFocus: false)
                        self.view.window?.makeKeyAndOrderFront(nil)
                        self.focus()
                        self.searchField.currentEditor()?.deleteBackward(nil)
                        return nil
                    }
                    if let characters = event.characters,
                       !characters.isEmpty,
                       characters.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 0xF700 }) {
                        self.closeQuickLook(restoreFocus: false)
                        self.view.window?.makeKeyAndOrderFront(nil)
                        self.focus()
                        self.searchField.currentEditor()?.insertText(characters)
                        return nil
                    }
                }
                return event
            }

            guard self.view.window?.isKeyWindow == true,
                  self.searchField.currentEditor() != nil,
                  event.keyCode == 49,
                  self.isNavigatingResults,
                  self.selectedFileURL() != nil
            else { return event }

            if event.isARepeat { return nil }
            self.toggleQuickLook()
            return nil
        }
    }

    private func toggleQuickLook() {
        guard let url = selectedFileURL() else { return }

        if previewIsOpen {
            closeQuickLook(restoreFocus: true)
            return
        }

        previewURL = url
        previewIsOpen = true
        guard let panel = QLPreviewPanel.shared() else {
            previewIsOpen = false
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        Log.debug("quicklook open: \(url.lastPathComponent)")
    }

    private func closeQuickLook(restoreFocus: Bool) {
        previewIsOpen = false
        previewURL = nil
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.isVisible {
            panel.orderOut(nil)
        }
        Log.debug("quicklook closed")
        if restoreFocus {
            restoreLauncherFocus()
        }
    }

    private func restoreLauncherFocus() {
        guard NSApp.isActive, let window = view.window, window.isVisible else { return }
        window.makeKeyAndOrderFront(nil)
        focus()
        DispatchQueue.main.async { [weak self] in
            self?.focus()
        }
    }

    // MARK: - Context menu

    private func makeContextMenu(for row: Int) -> NSMenu? {
        guard results.indices.contains(row) else { return nil }

        selectedIndex = row
        userNavigated = true
        isNavigatingResults = true
        tableView.reloadData()

        let result = results[row]
        contextResultID = result.id

        let menu = NSMenu()
        menu.autoenablesItems = false

        switch result.action {
        case .open(let url):
            if url.isFileURL {
                menu.addItem(contextItem("Open", #selector(contextOpen)))
                let reveal = contextItem("Show in Finder", #selector(contextReveal))
                reveal.isEnabled = FileManager.default.fileExists(atPath: url.path)
                menu.addItem(reveal)
                menu.addItem(.separator())
                menu.addItem(contextItem("Copy Path", #selector(contextCopyPath)))
            } else {
                menu.addItem(contextItem("Open Website", #selector(contextOpen)))
                menu.addItem(.separator())
                menu.addItem(contextItem("Copy URL", #selector(contextCopyURL)))
            }
        case .reveal(let url):
            let reveal = contextItem("Show in Finder", #selector(contextReveal))
            reveal.isEnabled = FileManager.default.fileExists(atPath: url.path)
            menu.addItem(reveal)
            menu.addItem(.separator())
            menu.addItem(contextItem("Copy Path", #selector(contextCopyPath)))
        case .run:
            menu.addItem(contextItem("Run", #selector(contextRun)))
        }

        return menu
    }

    private func contextItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func contextResult() -> SearchResult? {
        guard let id = contextResultID else { return nil }
        return results.first { $0.id == id }
    }

    private func fileURL(for result: SearchResult) -> URL? {
        switch result.action {
        case .open(let url), .reveal(let url):
            return url.isFileURL ? url : nil
        case .run:
            return nil
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    @objc private func contextOpen() {
        guard let result = contextResult() else { return }
        onChoose?(result, false)
    }

    @objc private func contextReveal() {
        guard let result = contextResult() else { return }
        onChoose?(result, true)
    }

    @objc private func contextRun() {
        guard let result = contextResult() else { return }
        onChoose?(result, false)
    }

    @objc private func contextCopyPath() {
        guard let result = contextResult(), let url = fileURL(for: result) else { return }
        copyToPasteboard(url.path)
        flashStatus("COPIED PATH")
    }

    @objc private func contextCopyURL() {
        guard let result = contextResult(),
              case .open(let url) = result.action,
              !url.isFileURL else { return }
        copyToPasteboard(url.absoluteString)
        flashStatus("COPIED URL")
    }

    // MARK: - Status

    func flashStatus(_ text: String) {
        statusWorkItem?.cancel()
        rootView.statusOverride = text
        let work = DispatchWorkItem { [weak self] in
            self?.rootView.statusOverride = nil
        }
        statusWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func clearStatus() {
        statusWorkItem?.cancel()
        statusWorkItem = nil
        rootView.statusOverride = nil
    }

    // MARK: - Debug helpers

    func debugContextMenuTitles(for row: Int) -> [String] {
        guard let menu = makeContextMenu(for: row) else { return [] }
        return menu.items.map { item in
            item.isSeparatorItem ? "---" : "\(item.title)\(item.isEnabled ? "" : " (disabled)")"
        }
    }

    func debugDragDescription(for row: Int) -> String {
        guard let writer = tableView(tableView, pasteboardWriterForRow: row) else { return "none" }
        if let url = writer as? NSURL {
            return url.absoluteString ?? "?"
        }
        return String(describing: type(of: writer))
    }
}

// MARK: - NSTextFieldDelegate

extension SearchViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSTextField === searchField else { return }
        Log.debug("query: \"\(searchField.stringValue)\"")
        clearStatus()
        isNavigatingResults = false
        resetSelectionOnNextUpdate = true
        userNavigated = false
        selectedIndex = 0
        rootView.query = searchField.stringValue
        engine?.search(searchField.stringValue)
        rootView.needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            chooseSelected(reveal: NSEvent.modifierFlags.contains(.command))
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        case #selector(NSResponder.insertTab(_:)):
            if isNavigatingResults {
                moveSelection(by: 1)
            } else {
                beginResultsNavigation()
            }
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            if isNavigatingResults {
                moveSelection(by: -1)
            } else {
                beginResultsNavigation()
            }
            return true
        default:
            return false
        }
    }
}

// MARK: - Table

extension SearchViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("result-row")
        let rowView: ResultRowView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? ResultRowView {
            rowView = reused
        } else {
            rowView = ResultRowView()
            rowView.identifier = identifier
        }
        rowView.configure(with: results[row], selected: row == selectedIndex)
        rowView.rowIndex = row
        rowView.menuProvider = { [weak self] row in
            self?.makeContextMenu(for: row)
        }
        return rowView
    }

    // MARK: - Drag out

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard results.indices.contains(row) else { return nil }
        switch results[row].action {
        case .open(let url), .reveal(let url):
            return url as NSURL
        case .run:
            // Commands are not files, but making them draggable as text keeps
            // a drag gesture from being interpreted as a click that runs them.
            let item = NSPasteboardItem()
            item.setString(results[row].title, forType: .string)
            return item
        }
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        suppressClick = true
        isDraggingResult = true
        rootView.statusOverride = nil
        if let row = rowIndexes.first, results.indices.contains(row) {
            draggedResult = results[row]
        } else {
            draggedResult = nil
        }
    }

    func tableView(
        _ tableView: NSTableView,
        draggingSession session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if !operation.isEmpty, let draggedResult {
            onDragOut?(draggedResult)
        }
        draggedResult = nil
        isDraggingResult = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            guard let window = self.view.window, !window.isKeyWindow else { return }
            self.onClose?()
        }
    }
}

// MARK: - Table view

final class ResultTableView: NSTableView {
    var onMouseDown: (() -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        if event.clickCount == 2, row >= 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onDoubleClick?(row)
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0 else { return nil }
        return contextMenuProvider?(row)
    }
}



// MARK: - Quick Look data source

extension SearchViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let previewURL else { return nil }
        Log.debug("quicklook item: \(previewURL.lastPathComponent)")
        return previewURL as NSURL
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window is QLPreviewPanel else { return }
        previewIsOpen = false
        previewURL = nil
        restoreLauncherFocus()
    }
}
