import AppKit

/// Publish existing files eagerly. Some media applications still read the
/// filename-list flavor; it must describe the same file as the modern URL.
enum ResultDragging {
    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let threshold: CGFloat = 4

    static func shouldBegin(from start: NSPoint, to point: NSPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) >= threshold
    }

    static func writer(for result: SearchResult) -> NSPasteboardWriting {
        switch result.action {
        case .open(let url), .reveal(let url):
            guard url.isFileURL else { return url as NSURL }
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            item.setPropertyList([url.path], forType: filenamesType)
            return item
        case .run:
            let item = NSPasteboardItem()
            item.setString(result.title, forType: .string)
            return item
        }
    }

    static func item(for result: SearchResult, at point: NSPoint) -> NSDraggingItem {
        let size = NSSize(width: 260, height: 36)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.95).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
            let icon: NSImage
            switch result.icon {
            case .file(let url): icon = IconCache.shared.icon(for: url)
            case .image, .glyph: icon = PixelGlyph.globe.image(size: 24, color: Theme.accent)
            }
            icon.draw(in: NSRect(x: 6, y: 6, width: 24, height: 24),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingMiddle
            (result.title as NSString).draw(in: NSRect(x: 38, y: 10, width: 214, height: 18),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                 .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
            return true
        }
        let item = NSDraggingItem(pasteboardWriter: writer(for: result))
        // Anchor the icon at the pointer, independent of where in the row the
        // mouse was pressed. No full-width row snapshot or animated subviews.
        item.setDraggingFrame(NSRect(x: point.x - 18, y: point.y - 18,
                                     width: size.width, height: size.height), contents: image)
        return item
    }
}

/// A separate source avoids NSTableView's row-drag image/selection machinery.
final class ResultDragSource: NSObject, NSDraggingSource {
    var onEnd: ((NSDragOperation) -> Void)?

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onEnd?(operation)
    }
}

final class ResultTableView: NSTableView {
    var onMouseDown: (() -> Void)?
    var onClick: ((Int) -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onScroll: (() -> Void)?
    var dragItemProvider: ((Int, NSPoint) -> NSDraggingItem?)?
    var onDragWillStart: ((Int) -> Void)?
    var onDragEnded: ((NSDragOperation) -> Void)?
    var onTrackingEnded: (() -> Void)?
    private(set) var isTrackingMouse = false
    private let dragSource = ResultDragSource()

    override func scrollWheel(with event: NSEvent) {
        onScroll?()
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        let row = self.row(at: start)
        guard row >= 0, dragItemProvider != nil else {
            super.mouseDown(with: event)
            return
        }
        isTrackingMouse = true
        onMouseDown?()
        defer {
            isTrackingMouse = false
            onTrackingEnded?()
        }
        // Start on movement in any direction, without a press-and-hold timer.
        // AppKit takes over tracking as soon as the native session is created.
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                          until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                if event.clickCount == 2 { onDoubleClick?(row) }
                else { onClick?(row) }
                return
            }
            let point = convert(next.locationInWindow, from: nil)
            guard ResultDragging.shouldBegin(from: start, to: point) else { continue }
            // A stale result cannot be dragged or turned into an accidental click.
            guard let item = dragItemProvider?(row, point) else { return }
            onDragWillStart?(row)
            dragSource.onEnd = { [weak self] operation in self?.onDragEnded?(operation) }
            let session = beginDraggingSession(with: [item], event: next, source: dragSource)
            session.draggingFormation = .none
            session.animatesToStartingPositionsOnCancelOrFail = false
            return
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return contextMenuProvider?(row)
    }
}
