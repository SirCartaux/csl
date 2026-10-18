import AppKit
import CoreImage
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
    private let placeholderView = SearchPlaceholderView()
    private let rootReveal = PixelRevealGrid()
    private var pixelOpenWork: DispatchWorkItem?
    private var pixelCloseWork: DispatchWorkItem?
    private var pixelRevealActive = false
    private var pixelClosing = false
    private var resultReveals: [(overlay: NSView, row: CALayer)] = []
    private var resultRevealWork: DispatchWorkItem?

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

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    var animationsEnabled: Bool {
        ProcessInfo.processInfo.environment["CSL_NO_PIXEL_ANIMATION"] != "1"
    }

    private var pixelCellSize: CGFloat {
        max(6, 10 * Theme.launcherScale)
    }

    /// 1.0 is the old timing; lower settings are slower (longer delays).
    private var pixelTimeScale: Double {
        SettingsStore.pixelAnimationBaseScale / SettingsStore.shared.pixelAnimationSpeed
    }

    private var smoothTimeScale: Double {
        1.0 / SettingsStore.shared.pixelAnimationSpeed
    }

    private var fieldCenter: CGPoint {
        CGPoint(x: searchField.frame.midX, y: searchField.frame.midY)
    }

    /// The mask layer's geometry is flipped relative to the root layer, so
    /// mirror Y for the radial wave.
    private var radialMaskCenter: CGPoint {
        CGPoint(
            x: fieldCenter.x,
            y: max(0, rootView.bounds.height - fieldCenter.y)
        )
    }

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
        rootView.addSubview(placeholderView)
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
        rootView.wantsLayer = true
        scrollView.wantsLayer = true
        if let cell = searchField.cell as? NSTextFieldCell {
            cell.placeholderAttributedString = nil
        }
        placeholderView.isHidden = !searchField.stringValue.isEmpty
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
        placeholderView.frame = searchField.frame

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

        cancelPixelAnimations()
        Theme.launcherScale = clamped
        searchField.applyLauncherScale()
        placeholderView.needsDisplay = true
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
        cancelPixelAnimations()
        clearStatus()
        isNavigatingResults = false
        if previewIsOpen {
            closeQuickLook(restoreFocus: false)
        }
        searchField.stringValue = ""
        placeholderView.isHidden = false
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

    // MARK: - Pixel reveal

    /// Build the masks during panel pre-warm so the hotkey path never creates
    /// layers while the user is waiting.
    func prewarmPixelAnimations() {
        guard animationsEnabled else { return }
        rootView.wantsLayer = true
        scrollView.wantsLayer = true
        guard rootView.bounds.width > 1, rootView.bounds.height > 1 else { return }
        rootReveal.prewarm(
            size: rootView.bounds.size,
            cellSize: pixelCellSize,
            style: .radial(center: radialMaskCenter)
        )
    }

    /// Hide the content behind a pixel mask before the panel is ordered front.
    func preparePixelOpen() {
        guard animationsEnabled else { return }
        cancelPixelAnimations()
        rootView.wantsLayer = true
        let size = rootView.bounds.size
        guard size.width > 1, size.height > 1, let layer = rootView.layer else { return }
        rootReveal.prepare(
            on: layer,
            size: size,
            cellSize: pixelCellSize,
            style: .radial(center: radialMaskCenter),
            visible: false
        )
        pixelRevealActive = true
    }

    /// Start the pixel wave only after the panel is key and the field focused.
    func startPixelOpen() {
        guard animationsEnabled, pixelRevealActive, let layerRoot = rootView.layer else { return }
        let total = rootReveal.animateOpen(
            on: layerRoot,
            spread: 0.12 * pixelTimeScale,
            jitter: 0.05 * pixelTimeScale,
            duration: 0.001 * pixelTimeScale
        )
        pixelOpenWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak layerRoot] in
            guard let self, let layerRoot else { return }
            self.rootReveal.clear(from: layerRoot)
            self.pixelRevealActive = false
        }
        pixelOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + total, execute: work)
    }

    /// Shrink the panel from the outside in, then hand control back to the
    /// window controller.
    func animatePixelClose(completion: @escaping () -> Void) {
        guard animationsEnabled, view.window?.isVisible == true else {
            completion()
            return
        }
        cancelPixelAnimations()
        pixelClosing = true
        rootView.wantsLayer = true
        let size = rootView.bounds.size
        guard size.width > 1, size.height > 1, let layer = rootView.layer else {
            pixelClosing = false
            completion()
            return
        }
        rootReveal.prepare(
            on: layer,
            size: size,
            cellSize: pixelCellSize,
            style: .radial(center: radialMaskCenter),
            visible: true
        )
        let total = rootReveal.animateClose(
            on: layer,
            spread: 0.12 * pixelTimeScale,
            jitter: 0.05 * pixelTimeScale,
            duration: 0.001 * pixelTimeScale
        )
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pixelClosing = false
            self.pixelRevealActive = false
            completion()
        }
        pixelCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + total, execute: work)
    }

    func cancelPixelAnimations() {
        pixelOpenWork?.cancel()
        pixelOpenWork = nil
        pixelCloseWork?.cancel()
        pixelCloseWork = nil
        cancelResultReveals()
        if let layer = rootView.layer {
            rootReveal.clear(from: layer)
        }
        pixelRevealActive = false
        pixelClosing = false
    }

    /// New rows slide in from the left with a Gaussian-blurred snapshot that
    /// resolves into the sharp row. Only visible new rows are animated.
    private func animateNewRows(_ indices: [Int]) {
        guard animationsEnabled,
              view.window?.isVisible == true,
              !pixelRevealActive,
              !pixelClosing,
              !indices.isEmpty else { return }

        cancelResultReveals()
        tableView.layoutSubtreeIfNeeded()

        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.location != NSNotFound else { return }
        let visibleIndices = indices.filter {
            $0 >= visible.location && $0 < NSMaxRange(visible)
        }
        guard !visibleIndices.isEmpty else { return }

        tableView.wantsLayer = true
        let scale = smoothTimeScale
        let slide = 0.22 * scale
        let fade = 0.10 * scale
        let total = slide + fade
        let slideFraction = slide / total
        let offset = 22 * Theme.launcherScale

        var reveals: [(overlay: NSView, row: CALayer)] = []
        for index in visibleIndices {
            guard let rowView = tableView.rowView(atRow: index, makeIfNecessary: true) else { continue }
            rowView.layoutSubtreeIfNeeded()
            rowView.wantsLayer = true
            guard let rowLayer = rowView.layer,
                  rowView.bounds.width > 1,
                  rowView.bounds.height > 1 else { continue }

            guard let rep = rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds) else { continue }
            rowView.cacheDisplay(in: rowView.bounds, to: rep)
            guard let cgImage = rep.cgImage,
                  let blurred = blurredImage(cgImage, radius: 6 * Theme.launcherScale) else { continue }
            let image = NSImage(cgImage: blurred, size: rowView.bounds.size)

            let overlay = ResultBlurOverlayView(image: image)
            overlay.frame = rowView.frame
            overlay.wantsLayer = true
            overlay.layer?.opacity = 0
            overlay.layer?.transform = CATransform3DMakeTranslation(-offset, 0, 0)
            tableView.addSubview(overlay)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            rowLayer.opacity = 1
            CATransaction.commit()
            rowLayer.removeAnimation(forKey: "resultRowFade")

            let slideAnimation = CABasicAnimation(keyPath: "transform.translation.x")
            slideAnimation.fromValue = -offset
            slideAnimation.toValue = 0
            slideAnimation.duration = total
            slideAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slideAnimation.fillMode = .both
            slideAnimation.isRemovedOnCompletion = true
            overlay.layer?.add(slideAnimation, forKey: "resultSlide")

            let overlayFade = CAKeyframeAnimation(keyPath: "opacity")
            overlayFade.values = [0.0, 1.0, 1.0, 0.0]
            overlayFade.keyTimes = [0.0, slideFraction, slideFraction, 1.0].map { NSNumber(value: $0) }
            overlayFade.duration = total
            overlayFade.fillMode = .both
            overlayFade.isRemovedOnCompletion = true
            overlay.layer?.opacity = 0
            overlay.layer?.add(overlayFade, forKey: "resultOverlayFade")

            let rowFade = CAKeyframeAnimation(keyPath: "opacity")
            rowFade.values = [0.0, 0.0, 1.0]
            rowFade.keyTimes = [0.0, slideFraction, 1.0].map { NSNumber(value: $0) }
            rowFade.duration = total
            rowFade.fillMode = .both
            rowFade.isRemovedOnCompletion = true
            rowLayer.add(rowFade, forKey: "resultRowFade")

            reveals.append((overlay, rowLayer))
        }

        guard !reveals.isEmpty else { return }
        resultReveals = reveals
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cancelResultReveals()
        }
        resultRevealWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.01, execute: work)
    }

    private func cancelResultReveals() {
        resultRevealWork?.cancel()
        resultRevealWork = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (overlay, row) in resultReveals {
            overlay.removeFromSuperview()
            row.opacity = 1
            row.removeAnimation(forKey: "resultRowFade")
        }
        CATransaction.commit()
        resultReveals.removeAll()
    }

    private func blurredImage(_ cgImage: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        let clamped = input.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        let cropped = output.cropped(to: input.extent)
        return Self.ciContext.createCGImage(cropped, from: cropped.extent)
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
        placeholderView.isHidden = !text.isEmpty
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
        if pixelRevealActive, !pixelClosing {
            // The list grew while the open wave was still running. Drop the
            // old mask rather than reveal the new area unmasked.
            cancelPixelAnimations()
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
        let previousIDs = Set(self.results.map(\.id))
        let resultsChanged = self.results.map(\.id) != results.map(\.id)
        if resultsChanged {
            cancelResultReveals()
        }

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

        let newRows = results.indices.filter { !previousIDs.contains(results[$0].id) }
        animateNewRows(newRows)
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
        placeholderView.isHidden = !searchField.stringValue.isEmpty
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

/// Blurred snapshot used for the smooth slide-in of new result rows.
private final class ResultBlurOverlayView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
