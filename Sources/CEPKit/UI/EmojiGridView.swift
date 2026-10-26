import AppKit
import QuartzCore

/// The scrolling character grid. Emoji and symbols occupy one cell; kaomoji
/// claim several cells so they can be shown at a readable size. The layout
/// packs both kinds into the same 12-column flow, which also makes mixed
/// search results look right.
final class EmojiGridView: NSView {
    var onActivate: ((EmojiItem, NSEvent.ModifierFlags, CGPoint) -> Void)?
    var onCopy: ((EmojiItem) -> Void)?
    var onCopyName: ((EmojiItem) -> Void)?
    var onFavorite: ((EmojiItem) -> Void)?
    var onHover: ((EmojiItem?) -> Void)?
    var onSelection: ((EmojiItem?) -> Void)?

    var emptyTitle = "NO RESULTS"
    var emptySubtitle = "TYPE TO SEARCH"
    var minimumHeight: CGFloat = 262

    private(set) var items: [EmojiItem] = []
    private(set) var selectedIndex: Int = 0
    private(set) var contentHeight: CGFloat = 262
    private var frames: [CGRect] = []
    private var rows: [Row] = []
    private var hoverIndex: Int?
    private var flashIndex: Int?
    private var flashWork: DispatchWorkItem?
    private var spanCache: [String: Int] = [:]
    private var lastWidth: CGFloat = 0
    private var favoriteLookup: Set<String> = []
    private var tracking: NSTrackingArea?

    private var padding: CGFloat { Theme.gridPadding }
    private var verticalPadding: CGFloat { Theme.gridVerticalPadding }
    private var cellWidth: CGFloat { Theme.cellWidth }
    private var cellHeight: CGFloat { Theme.cellHeight }

    private struct Row {
        var y: CGFloat
        var range: Range<Int>
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Character grid")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Data

    func setItems(_ newItems: [EmojiItem], resetSelection: Bool) {
        let previous = selectedItem
        items = newItems
        if resetSelection || selectedIndex >= items.count {
            selectedIndex = items.isEmpty ? -1 : 0
        }
        if selectedIndex < 0, !items.isEmpty {
            selectedIndex = 0
        }
        hoverIndex = nil
        flashIndex = nil
        layoutFrames(width: bounds.width > 1 ? bounds.width : Theme.panelWidth - Theme.sidebarWidth)
        needsDisplay = true
        if selectedItem != previous || resetSelection {
            onSelection?(selectedItem)
        }
    }

    func updateFavoriteLookup(_ lookup: Set<String>) {
        favoriteLookup = lookup
        needsDisplay = true
    }

    var selectedItem: EmojiItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    var selectedFrame: CGRect? {
        guard frames.indices.contains(selectedIndex) else { return nil }
        return frames[selectedIndex]
    }

    func layoutFrames(width: CGFloat, minimumHeight: CGFloat? = nil) {
        if let minimumHeight { self.minimumHeight = minimumHeight }
        guard width > 1 else { return }
        lastWidth = width
        let available = max(1, width - 2 * padding)
        let maxSpan = max(1, Int(floor(available / cellWidth)))

        var frames: [CGRect] = []
        frames.reserveCapacity(items.count)
        var rows: [Row] = []
        var x: CGFloat = padding
        var y: CGFloat = verticalPadding
        var rowStart = 0

        for (index, item) in items.enumerated() {
            var span = span(for: item)
            span = min(span, maxSpan)
            var frame = CGRect(
                x: x,
                y: y,
                width: CGFloat(span) * cellWidth,
                height: cellHeight
            )
            if frame.maxX > padding + available + 0.5 {
                if index > rowStart {
                    rows.append(Row(y: y, range: rowStart..<index))
                    rowStart = index
                }
                y += cellHeight
                x = padding
                frame.origin = CGPoint(x: x, y: y)
            }
            frames.append(frame)
            x += frame.width
        }

        if !items.isEmpty {
            rows.append(Row(y: y, range: rowStart..<items.count))
        }

        self.frames = frames
        self.rows = rows
        let natural = rows.isEmpty
            ? verticalPadding * 2 + cellHeight
            : (rows.last?.y ?? verticalPadding) + cellHeight + verticalPadding
        contentHeight = max(self.minimumHeight, natural)
        if abs(frame.height - contentHeight) > 0.5 {
            var newFrame = frame
            newFrame.size.height = contentHeight
            super.setFrameSize(newFrame.size)
        }
    }

    private func span(for item: EmojiItem) -> Int {
        guard item.isKaomoji else { return 1 }
        if let cached = spanCache[item.text] { return cached }
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.kaomojiFont]
        let width = (item.text as NSString).size(withAttributes: attributes).width
        let span = max(3, min(6, Int(ceil((width + 10) / cellWidth))))
        spanCache[item.text] = span
        return span
    }

    // MARK: - Selection

    func select(index: Int, notify: Bool = true, scroll: Bool = true) {
        guard !items.isEmpty else { return }
        let clamped = min(max(index, 0), items.count - 1)
        let changed = clamped != selectedIndex
        selectedIndex = clamped
        hoverIndex = nil
        needsDisplay = true
        if scroll { scrollSelectionToVisible() }
        if notify, changed {
            onSelection?(selectedItem)
        }
    }

    func moveVertical(_ delta: Int) {
        guard !items.isEmpty, !rows.isEmpty else { return }
        guard let currentRow = rows.firstIndex(where: { $0.range.contains(selectedIndex) }) else {
            select(index: 0)
            return
        }
        let targetRow = min(max(currentRow + delta, 0), rows.count - 1)
        guard targetRow != currentRow else { return }
        let currentCenter = frames[selectedIndex].midX
        let candidates = rows[targetRow].range
        var best = candidates.lowerBound
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in candidates {
            let distance = abs(frames[index].midX - currentCenter)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        select(index: best)
    }

    func moveHorizontal(_ delta: Int) {
        guard !items.isEmpty else { return }
        select(index: selectedIndex + delta)
    }

    func movePage(_ direction: Int) {
        let visible = enclosingScrollView?.contentView.bounds.height ?? minimumHeight
        let rowsPerPage = max(1, Int(floor(visible / cellHeight)) - 1)
        moveVertical(direction * rowsPerPage)
    }

    func selectFirst() {
        guard !items.isEmpty else { return }
        select(index: 0)
    }

    func selectLast() {
        guard !items.isEmpty else { return }
        select(index: items.count - 1)
    }

    func scrollSelectionToVisible() {
        guard frames.indices.contains(selectedIndex) else { return }
        let frame = frames[selectedIndex]
        scrollToVisible(frame.insetBy(dx: 0, dy: -6))
    }

    func flash(index: Int? = nil) {
        flashIndex = index ?? selectedIndex
        needsDisplay = true
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flashIndex = nil
            self?.needsDisplay = true
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    func refreshHoverFromMouse() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let index = bounds.contains(point) ? index(at: point) : nil
        updateHover(index)
    }

    // MARK: - Geometry

    private func index(at point: CGPoint) -> Int? {
        guard point.x >= 0, point.y >= 0, point.x <= bounds.width, point.y <= bounds.height else { return nil }
        let rowIndex = Int(floor((point.y - verticalPadding) / cellHeight))
        guard rows.indices.contains(rowIndex) else { return nil }
        let row = rows[rowIndex]
        for index in row.range where frames[index].insetBy(dx: -1, dy: 0).contains(point) {
            return index
        }
        return nil
    }

    private func updateHover(_ index: Int?) {
        guard hoverIndex != index else { return }
        hoverIndex = index
        needsDisplay = true
        onHover?(index.flatMap { items.indices.contains($0) ? items[$0] : nil })
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        tracking = area
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(index(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        Log.debug("grid mouseDown at \(point) in \(bounds)")
        guard let index = index(at: point) else {
            Log.debug("grid mouseDown missed a cell")
            return
        }
        let item = items[index]
        Log.debug("grid mouseDown index \(index) item \(item.text) flags \(event.modifierFlags.rawValue)")
        select(index: index, notify: true, scroll: false)
        flash(index: index)
        onActivate?(item, event.modifierFlags, point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = index(at: point) else { return }
        select(index: index, notify: true, scroll: false)
        let item = items[index]
        let menu = NSMenu(title: "")
        menu.addItem(menuItem("INSERT", action: #selector(menuInsert(_:)), index: index))
        menu.addItem(menuItem("COPY", action: #selector(menuCopy(_:)), index: index))
        menu.addItem(menuItem("COPY NAME", action: #selector(menuCopyName(_:)), index: index))
        menu.addItem(.separator())
        let favoriteTitle = favoriteLookup.contains(item.text) ? "UNPIN FROM FAVORITES" : "PIN TO FAVORITES"
        menu.addItem(menuItem(favoriteTitle, action: #selector(menuFavorite(_:)), index: index))
        menu.popUp(positioning: nil, at: point, in: self)
    }

    private func menuItem(_ title: String, action: Selector, index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = index
        return item
    }

    @objc private func menuInsert(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, items.indices.contains(index) else { return }
        selectedIndex = index
        onActivate?(items[index], [], frames[index].center)
    }

    @objc private func menuCopy(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, items.indices.contains(index) else { return }
        onCopy?(items[index])
    }

    @objc private func menuCopyName(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, items.indices.contains(index) else { return }
        onCopyName?(items[index])
    }

    @objc private func menuFavorite(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int, items.indices.contains(index) else { return }
        onFavorite?(items[index])
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard !items.isEmpty else {
            drawEmptyState()
            return
        }

        for (index, item) in items.enumerated() {
            let cell = frames[index]
            guard cell.intersects(dirtyRect) else { continue }
            drawCell(item: item, cell: cell, index: index)
        }
    }

    private func drawCell(item: EmojiItem, cell: CGRect, index: Int) {
        let isSelected = index == selectedIndex
        let isHovered = index == hoverIndex
        let isFlashing = index == flashIndex

        if isSelected {
            PixelDraw.fill(cell.insetBy(dx: 3, dy: 3), Theme.bgSelected)
        } else if isHovered {
            PixelDraw.fill(cell.insetBy(dx: 3, dy: 3), Theme.bgRaised.withAlphaComponent(0.9))
        }

        if isFlashing {
            PixelDraw.fill(cell.insetBy(dx: 2, dy: 2), Theme.accent.withAlphaComponent(0.10))
        }

        let contentRect = cell.insetBy(dx: 5, dy: 4)
        switch item.kind {
        case .emoji:
            drawEmoji(item.text, in: contentRect, selected: isSelected)
        case .symbol:
            drawSymbol(item.text, in: contentRect, selected: isSelected)
        case .kaomoji:
            drawKaomoji(item.text, in: contentRect, selected: isSelected)
        }

        if favoriteLookup.contains(item.text) {
            PixelDraw.star(
                x: cell.maxX - 10,
                y: cell.minY + 5,
                unit: 1,
                color: isSelected ? Theme.accent : Theme.accentDim
            )
        }

        if isSelected {
            PixelDraw.frame(
                cell.insetBy(dx: 2, dy: 2),
                thickness: 2,
                color: Theme.accent,
                notch: 3
            )
            PixelDraw.frame(
                cell.insetBy(dx: 5, dy: 5),
                thickness: 1,
                color: Theme.accent.withAlphaComponent(0.18),
                notch: 2
            )
        } else if isHovered {
            PixelDraw.frame(
                cell.insetBy(dx: 2, dy: 2),
                thickness: 1,
                color: Theme.borderBright,
                notch: 3
            )
        }

        if isFlashing {
            PixelDraw.frame(
                cell.insetBy(dx: 1, dy: 1),
                thickness: 1,
                color: Theme.success.withAlphaComponent(0.9),
                notch: 3
            )
        }
    }

    private func drawEmoji(_ text: String, in rect: CGRect, selected: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.emojiFont
        ]
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        let target = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width + 2,
            height: size.height
        )
        string.draw(in: target, withAttributes: attributes)
    }

    private func drawSymbol(_ text: String, in rect: CGRect, selected: Bool) {
        var font = Theme.symbolFont
        var size = (text as NSString).size(withAttributes: [.font: font])
        if size.width > rect.width, let smaller = NSFont(name: "Apple Symbols", size: 17) {
            font = smaller
            size = (text as NSString).size(withAttributes: [.font: font])
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: selected ? Theme.accent : Theme.text
        ]
        (text as NSString).draw(
            in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width + 2,
                height: size.height
            ),
            withAttributes: attributes
        )
    }

    private func drawKaomoji(_ text: String, in rect: CGRect, selected: Bool) {
        var font = Theme.kaomojiFont
        var size = (text as NSString).size(withAttributes: [.font: font])
        var pointSize = font.pointSize
        while size.width > rect.width - 2, pointSize > 8 {
            pointSize -= 0.5
            font = NSFont(name: "Menlo", size: pointSize)
                ?? NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
            size = (text as NSString).size(withAttributes: [.font: font])
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: selected ? Theme.accent : Theme.text
        ]
        (text as NSString).draw(
            in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width + 2,
                height: size.height
            ),
            withAttributes: attributes
        )
    }

    private func drawEmptyState() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(13),
            .foregroundColor: Theme.text
        ]
        let title = emptyTitle as NSString
        let size = title.size(withAttributes: attributes)
        title.draw(
            in: CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - 18,
                width: size.width + 4,
                height: size.height
            ),
            withAttributes: attributes
        )

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(9),
            .foregroundColor: Theme.textFaint
        ]
        let subtitle = emptySubtitle as NSString
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        subtitle.draw(
            in: CGRect(
                x: bounds.midX - subtitleSize.width / 2,
                y: bounds.midY + 6,
                width: subtitleSize.width + 4,
                height: subtitleSize.height
            ),
            withAttributes: subtitleAttributes
        )
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
