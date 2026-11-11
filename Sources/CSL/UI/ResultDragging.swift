import AppKit

/// Use AppKit's native URL writer so the drag carries a real file reference.
/// Legacy non-UTI types cannot be placed on an NSDraggingItem on modern macOS.
enum ResultDragging {
    static let threshold: CGFloat = 4
    static let previewSize = NSSize(width: 260, height: 36)
    /// Rasterize at 2x so the preview stays crisp on Retina without asking
    /// AppKit to render a custom image representation during the drag.
    static let previewScale: CGFloat = 2

    static func shouldBegin(from start: NSPoint, to point: NSPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) >= threshold
    }

    static func writer(for result: SearchResult) -> NSPasteboardWriting {
        switch result.action {
        case .open(let url), .reveal(let url):
            return url as NSURL
        case .run, .manage, .complete:
            let item = NSPasteboardItem()
            item.setString(result.title, forType: .string)
            return item
        }
    }

    /// The exact pixels handed to AppKit for the drag preview. The icon and
    /// text are resolved and rasterized here, before the session starts, so
    /// the drag item has no drawing handler that AppKit could invoke later.
    static func previewImage(for result: SearchResult) -> NSImage {
        let icon: NSImage
        switch result.icon {
        case .file(let url):
            icon = IconCache.shared.icon(for: url)
        case .image, .glyph:
            icon = PixelGlyph.globe.image(size: 24, color: Theme.accent)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let background = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        let title = result.title as NSString

        // Draw the design once into a temporary image, then immediately copy
        // those pixels into a bitmap representation. Only the bitmap is exposed
        // to AppKit; the drawing handler is released with `source`.
        let source = NSImage(size: previewSize, flipped: true) { rect in
            background.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
            icon.draw(
                in: NSRect(x: 6, y: 6, width: 24, height: 24),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            title.draw(
                in: NSRect(x: 38, y: 10, width: 214, height: 18),
                withAttributes: textAttributes
            )
            return true
        }

        let pixelsWide = Int(previewSize.width * previewScale)
        let pixelsHigh = Int(previewSize.height * previewScale)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return source
        }
        representation.size = previewSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        source.draw(in: NSRect(origin: .zero, size: previewSize))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: previewSize)
        image.addRepresentation(representation)
        return image
    }

    struct PreparedDragItem {
        let item: NSDraggingItem
        let image: NSImage
    }

    static func preparedItem(for result: SearchResult, at point: NSPoint) -> PreparedDragItem {
        let image = previewImage(for: result)
        let item = NSDraggingItem(pasteboardWriter: writer(for: result))
        // Anchor the icon at the pointer, independent of where in the row the
        // mouse was pressed. No full-width row snapshot or animated subviews.
        item.setDraggingFrame(
            NSRect(
                x: point.x - 18,
                y: point.y - 18,
                width: previewSize.width,
                height: previewSize.height
            ),
            contents: image
        )
        return PreparedDragItem(item: item, image: image)
    }

    static func item(for result: SearchResult, at point: NSPoint) -> NSDraggingItem {
        preparedItem(for: result, at: point).item
    }
}

/// Diagnostic-only high-frequency drag trace. It records the event point AppKit
/// reports for the drag, the actual hardware pointer position at callback time,
/// and the resulting tooltip origin. Enabled only with CSL_DRAG_TRACE=1; normal
/// drags never allocate or write anything.
final class DragTrace {
    static let enabled = ProcessInfo.processInfo.environment["CSL_DRAG_TRACE"] == "1"
    static let shared = DragTrace()

    private var lines: [String] = []
    private var start: TimeInterval = 0
    private var lastTime: TimeInterval = 0
    private var previousPoint: NSPoint?
    private var maxLag: Double = 0
    private var totalMoves = 0
    private var appliedPointer: NSPoint?
    private let path = "/tmp/csl-drag-trace.csv"
    private let summaryPath = "/tmp/csl-drag-trace-summary.txt"

    private init() {}

    func begin(screenPoint: NSPoint) {
        guard Self.enabled else { return }
        start = ProcessInfo.processInfo.systemUptime
        lastTime = start
        previousPoint = screenPoint
        maxLag = 0
        totalMoves = 0
        appliedPointer = nil
        lines = ["elapsed_s,event_x,event_y,mouse_x,mouse_y,lag_x,lag_y,lag_px,interval_ms,tooltip_x,tooltip_y,applied_x,applied_y,applied_delta_px"]
        let mouse = NSEvent.mouseLocation
        let lag = hypot(mouse.x - screenPoint.x, mouse.y - screenPoint.y)
        maxLag = lag
        lines.append(String(format: "%.6f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,0.000,%.3f,%.3f,%.3f,%.3f,%.3f",
                           0, screenPoint.x, screenPoint.y, mouse.x, mouse.y,
                           mouse.x - screenPoint.x, mouse.y - screenPoint.y, lag,
                           screenPoint.x - 18, screenPoint.y - 18,
                           appliedPointer?.x ?? 0, appliedPointer?.y ?? 0,
                           appliedPointer.map { hypot($0.x - mouse.x, $0.y - mouse.y) } ?? 0))
        flush()
    }

    func move(screenPoint: NSPoint) {
        guard Self.enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation
        let lagX = mouse.x - screenPoint.x
        let lagY = mouse.y - screenPoint.y
        let lag = hypot(lagX, lagY)
        maxLag = max(maxLag, lag)
        totalMoves += 1
        let interval = (now - lastTime) * 1000
        lastTime = now
        lines.append(String(format: "%.6f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f",
                           now - start, screenPoint.x, screenPoint.y, mouse.x, mouse.y,
                           lagX, lagY, lag, interval,
                           screenPoint.x - 18, screenPoint.y - 18,
                           appliedPointer?.x ?? 0, appliedPointer?.y ?? 0,
                           appliedPointer.map { hypot($0.x - mouse.x, $0.y - mouse.y) } ?? 0))
        previousPoint = screenPoint
        if totalMoves % 100 == 0 { flush() }
    }

    func noteApplied(pointerFromFrame: NSPoint) {
        guard Self.enabled else { return }
        appliedPointer = pointerFromFrame
    }

    func end(screenPoint: NSPoint, operation: NSDragOperation) {
        guard Self.enabled else { return }
        move(screenPoint: screenPoint)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let summary = """
        moves=\(totalMoves)
        elapsed_s=\(String(format: "%.3f", elapsed))
        max_lag_px=\(String(format: "%.3f", maxLag))
        final_lag_px=\(String(format: "%.3f", hypot(NSEvent.mouseLocation.x - screenPoint.x, NSEvent.mouseLocation.y - screenPoint.y)))
        operation=\(operation.rawValue)
        """
        lines.append("# " + summary.replacingOccurrences(of: "\n", with: " "))
        flush()
        try? summary.write(toFile: summaryPath, atomically: true, encoding: .utf8)
        Log.always("drag trace written: \(path) (\(summary.replacingOccurrences(of: "\n", with: " ")))")
    }

    private func flush() {
        guard Self.enabled, !lines.isEmpty else { return }
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

/// A separate source avoids NSTableView's row-drag image/selection machinery.
/// `movedTo` deliberately moves the native drag item to the *current* pointer.
/// AppKit may deliver that callback late while the destination is busy; without
/// this, the drag image animates through the stale event point and appears to
/// crawl behind the pointer. Finder jumps straight to the pointer after the
/// destination answers, so we do the same.
final class ResultDragSource: NSObject, NSDraggingSource {
    var onEnd: ((NSDragOperation) -> Void)?
    private var beganAt: TimeInterval = 0
    private weak var sourceView: NSView?
    private var draggingItem: NSDraggingItem?
    private var draggingImage: NSImage?
    private var lastPointerScreen: NSPoint?
    private let pointerOffset: CGFloat = 18

    func prepare(item: NSDraggingItem, image: NSImage, in view: NSView) {
        draggingItem = item
        draggingImage = image
        sourceView = view
        lastPointerScreen = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        beganAt = ProcessInfo.processInfo.systemUptime
        DragTrace.shared.begin(screenPoint: screenPoint)
        Log.debug("drag session began at \(screenPoint)")
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = false
        jumpTooltipToCurrentPointer(session: session)
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        // The destination can block this callback for seconds. Snap to the
        // pointer's position now instead of letting AppKit interpolate from
        // the stale event point.
        jumpTooltipToCurrentPointer(session: session)
        DragTrace.shared.move(screenPoint: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        DragTrace.shared.end(screenPoint: screenPoint, operation: operation)
        Log.debug("drag session ended at \(screenPoint) after \(ProcessInfo.processInfo.systemUptime - beganAt)s operation=\(operation.rawValue)")
        draggingItem = nil
        draggingImage = nil
        sourceView = nil
        lastPointerScreen = nil
        onEnd?(operation)
    }

    private func jumpTooltipToCurrentPointer(session: NSDraggingSession) {
        guard let view = sourceView,
              let image = draggingImage,
              let window = view.window else { return }
        let mouse = NSEvent.mouseLocation
        if let last = lastPointerScreen,
           abs(mouse.x - last.x) < 0.25, abs(mouse.y - last.y) < 0.25 {
            return
        }
        lastPointerScreen = mouse
        let inWindow = window.convertPoint(fromScreen: mouse)
        let local = view.convert(inWindow, from: nil)
        let size = draggingItem?.draggingFrame.size ?? ResultDragging.previewSize
        let frame = NSRect(
            x: local.x - pointerOffset,
            y: local.y - pointerOffset,
            width: size.width,
            height: size.height
        )

        // The item passed to beginDraggingSession is only a template. The
        // live item is owned by the session and must be changed through
        // enumeration, otherwise the window server keeps its old image.
        var appliedFrame: NSRect?
        session.enumerateDraggingItems(
            options: [],
            for: view,
            classes: [NSURL.self, NSString.self],
            searchOptions: [:]
        ) { item, _, _ in
            item.setDraggingFrame(frame, contents: image)
            appliedFrame = item.draggingFrame
        }
        if appliedFrame == nil, let item = draggingItem {
            // Fallback for command/string items that were not enumerated.
            item.setDraggingFrame(frame, contents: image)
            appliedFrame = item.draggingFrame
        }
        guard let appliedFrame else { return }
        let frameInWindow = view.convert(appliedFrame.origin, to: nil)
        let frameOnScreen = window.convertPoint(toScreen: frameInWindow)
        // The item frame origin is the top-left in a flipped table view; the
        // screen Y axis points up, so the pointer is 18pt below that origin.
        DragTrace.shared.noteApplied(
            pointerFromFrame: NSPoint(x: frameOnScreen.x + pointerOffset, y: frameOnScreen.y - pointerOffset)
        )
    }
}

final class ResultTableView: NSTableView {
    var onMouseDown: (() -> Void)?
    var onClick: ((Int) -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var onScroll: (() -> Void)?
    var dragItemProvider: ((Int, NSPoint) -> ResultDragging.PreparedDragItem?)?
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
            guard let prepared = dragItemProvider?(row, point) else { return }
            onDragWillStart?(row)
            dragSource.prepare(item: prepared.item, image: prepared.image, in: self)
            dragSource.onEnd = { [weak self] operation in self?.onDragEnded?(operation) }
            let session = beginDraggingSession(with: [prepared.item], event: next, source: dragSource)
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
