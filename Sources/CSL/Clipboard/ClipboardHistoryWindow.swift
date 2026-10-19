import AppKit

enum ClipboardHistoryLayout {
    static let windowSize = NSSize(width: 840, height: 620)
    static let inset: CGFloat = 28
    static let headerHeight: CGFloat = 58
    static let footerHeight: CGFloat = 36

    static func panelRect(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: inset, dy: inset)
    }

    static func headerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: headerHeight)
    }

    static func searchRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        let header = headerRect(in: bounds)
        return CGRect(x: panel.minX + 24, y: header.maxY + 16, width: panel.width - 48, height: 36)
    }

    static func footerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(x: panel.minX, y: panel.maxY - footerHeight, width: panel.width, height: footerHeight)
    }

    static func listRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        let search = searchRect(in: bounds)
        let footer = footerRect(in: bounds)
        return CGRect(
            x: panel.minX + 16,
            y: search.maxY + 12,
            width: panel.width - 32,
            height: max(10, footer.minY - search.maxY - 22)
        )
    }
}

final class ClipboardHistoryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: ClipboardHistoryLayout.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .normal
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.fullScreenAuxiliary]
        title = "CSL Clipboard History"
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

final class ClipboardHistoryRootView: NSView {
    let searchField = PixelField(placeholder: "SEARCH CLIPBOARD…")
    let scrollView = NSScrollView()
    let tableView = ClipboardHistoryTableView()
    let closeButton = PixelButton("X", style: .ghost)
    let clearButton = PixelButton("CLEAR", style: .ghost)
    let glowView = GlowView(frame: .zero)

    var onClose: (() -> Void)?
    var onClear: (() -> Void)?
    var onFilter: (() -> Void)?
    var onSubmit: (() -> Void)?

    var usedBytes = 0
    var maxBytes = ClipboardHistoryStore.maxBytes
    var itemCount = 0
    var storeEmpty = true
    var isFiltering = false

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
        addSubview(searchField)
        searchField.onTextChange = { [weak self] in self?.onFilter?() }
        searchField.onSubmit = { [weak self] in self?.onSubmit?() }

        buildTable()
        addSubview(scrollView)

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        addSubview(closeButton)

        clearButton.target = self
        clearButton.action = #selector(clearPressed)
        addSubview(clearButton)

        glowView.panelRectProvider = { bounds in
            ClipboardHistoryLayout.panelRect(in: bounds)
        }
        glowView.ledRectProvider = nil
        addSubview(glowView)
    }

    private func buildTable() {
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

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard"))
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
    }

    @objc private func closePressed() {
        onClose?()
    }

    @objc private func clearPressed() {
        onClear?()
    }

    func startGlow() { glowView.startPulse() }
    func stopGlow() { glowView.stopPulse() }

    func focusSearch() {
        window?.makeFirstResponder(searchField.textField)
        searchField.textField.styleEditor()
    }

    override func layout() {
        super.layout()
        let panel = ClipboardHistoryLayout.panelRect(in: bounds)
        let header = ClipboardHistoryLayout.headerRect(in: bounds)
        let search = ClipboardHistoryLayout.searchRect(in: bounds)
        let list = ClipboardHistoryLayout.listRect(in: bounds)

        closeButton.frame = CGRect(x: panel.maxX - 42, y: header.minY + 15, width: 28, height: 26)
        clearButton.frame = CGRect(x: closeButton.frame.minX - 82, y: header.minY + 15, width: 72, height: 26)
        searchField.frame = search
        scrollView.frame = list

        if let column = tableView.tableColumns.first {
            column.width = list.width - 8
        }
        tableView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(1, list.width - (scrollView.hasVerticalScroller ? 8 : 0)),
            height: max(list.height, CGFloat(itemCount) * tableView.rowHeight)
        )
        glowView.frame = bounds
    }

    override func draw(_ dirtyRect: NSRect) {
        let panel = ClipboardHistoryLayout.panelRect(in: bounds)
        let header = ClipboardHistoryLayout.headerRect(in: bounds)
        let footer = ClipboardHistoryLayout.footerRect(in: bounds)
        let list = ClipboardHistoryLayout.listRect(in: bounds)

        PixelDraw.fill(panel.offsetBy(dx: 6, dy: 6), Theme.shadow)
        PixelDraw.fill(panel, Theme.bg)
        let borderColor = Theme.border.blended(withFraction: 0.20, of: Theme.accent) ?? Theme.border
        PixelDraw.frame(panel, thickness: 1, color: borderColor, notch: 3)

        PixelDraw.fill(header, Theme.bgRaised)
        PixelDraw.hLine(x: header.minX, y: header.maxY - 1, width: header.width, color: Theme.line)

        let glyph = PixelGlyph.clipboard.image(size: 18, color: Theme.accent)
        glyph.draw(in: CGRect(x: panel.minX + 22, y: header.minY + 19, width: 18, height: 18))

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(17),
            .foregroundColor: Theme.accent
        ]
        let title = "CLIPBOARD"
        let titleSize = (title as NSString).size(withAttributes: titleAttributes)
        (title as NSString).draw(
            in: CGRect(x: panel.minX + 50, y: header.minY + 13, width: titleSize.width + 4, height: 22),
            withAttributes: titleAttributes
        )
        ("HISTORY" as NSString).draw(
            in: CGRect(x: panel.minX + 50 + titleSize.width + 10, y: header.minY + 19, width: 120, height: 12),
            withAttributes: [
                .font: Theme.display(8.5),
                .foregroundColor: Theme.textFaint
            ]
        )

        drawStorage(panel: panel, header: header)

        PixelDraw.hLine(x: footer.minX, y: footer.minY, width: footer.width, color: Theme.line)
        drawFooter(footer)

        if itemCount == 0 {
            drawEmptyState(in: list)
        }
    }

    private func drawStorage(panel: CGRect, header: CGRect) {
        let right = clearButton.frame.minX - 20
        let width: CGFloat = 172
        let rect = CGRect(x: right - width, y: header.minY + 11, width: width, height: 34)
        let fraction = max(0, min(1, Double(usedBytes) / Double(max(1, maxBytes))))
        let percent = Int((fraction * 100).rounded())

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(usedBytes), countStyle: .memory)
        let capacity = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .memory)
        ("\(bytes) / \(capacity)" as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 10),
            withAttributes: [
                .font: Theme.display(7.5),
                .foregroundColor: Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
        let percentText = usedBytes > 0 && percent == 0 ? "<1%" : "\(percent)%"
        (percentText as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 10),
            withAttributes: [
                .font: Theme.display(7.5),
                .foregroundColor: fraction > 0.9 ? Theme.danger : Theme.accentDim,
                .paragraphStyle: NSMutableParagraphStyle()
            ]
        )

        let bar = CGRect(x: rect.minX, y: rect.minY + 15, width: rect.width, height: 6)
        let blocks = 28
        let gap: CGFloat = 2
        let block = max(1, floor((bar.width - CGFloat(blocks - 1) * gap) / CGFloat(blocks)))
        for index in 0..<blocks {
            let x = bar.minX + CGFloat(index) * (block + gap)
            let filled = Double(index) / Double(blocks) < fraction
            PixelDraw.fill(
                CGRect(x: x, y: bar.minY, width: block, height: bar.height),
                filled ? Theme.accent : Theme.line
            )
        }
    }

    private func drawFooter(_ rect: CGRect) {
        var cursor = rect.minX + 20
        cursor = drawHint(key: "UP/DOWN", label: "BROWSE", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "ENTER", label: "COPY", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "CMD+P", label: "PIN", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "CMD+DEL", label: "DELETE", at: cursor, centerY: rect.midY)
        _ = drawHint(key: "ESC", label: "CLOSE", at: cursor, centerY: rect.midY)

        let count = "\(itemCount) \(itemCount == 1 ? "ITEM" : "ITEMS")"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (count as NSString).draw(
            in: CGRect(x: rect.maxX - 170, y: rect.minY + 11, width: 150, height: 12),
            withAttributes: [
                .font: Theme.display(7.5),
                .foregroundColor: Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawHint(key: String, label: String, at x: CGFloat, centerY: CGFloat) -> CGFloat {
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7.5),
            .foregroundColor: Theme.textDim
        ]
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7),
            .foregroundColor: Theme.textFaint
        ]
        let keyWidth = (key as NSString).size(withAttributes: keyAttributes).width + 10
        let cap = CGRect(x: x, y: centerY - 8, width: keyWidth, height: 16)
        PixelDraw.frame(cap, thickness: 1, color: Theme.border, notch: 2)
        (key as NSString).draw(
            in: CGRect(x: cap.minX + 5, y: cap.minY + 3, width: keyWidth - 6, height: 10),
            withAttributes: keyAttributes
        )
        let labelX = cap.maxX + 6
        (label as NSString).draw(
            in: CGRect(x: labelX, y: cap.minY + 3, width: 90, height: 10),
            withAttributes: labelAttributes
        )
        return labelX + (label as NSString).size(withAttributes: labelAttributes).width + 14
    }

    private func drawEmptyState(in rect: CGRect) {
        let title: String
        let subtitle: String
        if storeEmpty {
            title = "CLIPBOARD IS EMPTY"
            subtitle = "COPY TEXT, IMAGES OR FILES"
        } else if isFiltering {
            title = "NO MATCHES"
            subtitle = "TRY A DIFFERENT FILTER"
        } else {
            title = "NOTHING HERE"
            subtitle = "COPY SOMETHING TO START"
        }

        let glyph = PixelGlyph.clipboard.image(size: 30, color: Theme.textFaint.withAlphaComponent(0.5))
        glyph.draw(in: CGRect(
            x: rect.midX - 15,
            y: rect.midY - 43,
            width: 30,
            height: 30
        ))

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (title as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY + 2, width: rect.width, height: 18),
            withAttributes: [
                .font: Theme.displayBold(11),
                .foregroundColor: Theme.textDim,
                .paragraphStyle: paragraph
            ]
        )
        (subtitle as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY + 23, width: rect.width, height: 12),
            withAttributes: [
                .font: Theme.display(8),
                .foregroundColor: Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if ClipboardHistoryLayout.headerRect(in: bounds).contains(point) {
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
