import AppKit

/// Invisible ten-point border around the launcher. Dragging any edge or corner
/// scales the whole panel uniformly. The window frame is always rebuilt around
/// its original center, so resizing never pushes the panel into a corner.
final class ResizeHandleView: NSView {
    var onScaleChanged: ((CGFloat) -> Void)?
    var onScaleCommitted: (() -> Void)?

    private enum Edge: Hashable {
        case left, right, top, bottom
    }

    private var activeEdges: Set<Edge> = []
    private var startFrame: NSRect = .zero
    private var startScale: CGFloat = 1
    private var startMouse: NSPoint = .zero
    private var startPanelHalfWidth: CGFloat = 0
    private var startPanelHalfHeight: CGFloat = 0
    private var screen: NSScreen?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var edgeWidth: CGFloat {
        max(8, Theme.ls(10))
    }

    private func edges(at point: NSPoint) -> Set<Edge> {
        let panel = Layout.panelRect(in: bounds)
        let edge = edgeWidth
        var edges = Set<Edge>()
        if point.x >= panel.minX - edge, point.x <= panel.minX + edge,
           point.y >= panel.minY - edge, point.y <= panel.maxY + edge {
            edges.insert(.left)
        }
        if point.x >= panel.maxX - edge, point.x <= panel.maxX + edge,
           point.y >= panel.minY - edge, point.y <= panel.maxY + edge {
            edges.insert(.right)
        }
        if point.y >= panel.minY - edge, point.y <= panel.minY + edge,
           point.x >= panel.minX - edge, point.x <= panel.maxX + edge {
            edges.insert(.top)
        }
        if point.y >= panel.maxY - edge, point.y <= panel.maxY + edge,
           point.x >= panel.minX - edge, point.x <= panel.maxX + edge {
            edges.insert(.bottom)
        }
        return edges
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local), !edges(at: local).isEmpty else { return nil }
        return self
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        let panel = Layout.panelRect(in: bounds)
        let edge = edgeWidth
        let vertical = CGRect(x: panel.minX - edge, y: panel.minY - edge,
                              width: 2 * edge, height: panel.height + 2 * edge)
        let horizontal = CGRect(x: panel.minX - edge, y: panel.minY - edge,
                                width: panel.width + 2 * edge, height: 2 * edge)
        addCursorRect(vertical, cursor: .resizeLeftRight)
        addCursorRect(vertical.offsetBy(dx: panel.width, dy: 0), cursor: .resizeLeftRight)
        addCursorRect(horizontal, cursor: .resizeUpDown)
        addCursorRect(horizontal.offsetBy(dx: 0, dy: panel.height), cursor: .resizeUpDown)

        // AppKit only ships axis-aligned resize cursors before macOS 15;
        // corners use the horizontal one and still resize both axes.
        let corners = [
            CGRect(x: panel.minX - edge, y: panel.minY - edge, width: 2 * edge, height: 2 * edge),
            CGRect(x: panel.maxX - edge, y: panel.minY - edge, width: 2 * edge, height: 2 * edge),
            CGRect(x: panel.minX - edge, y: panel.maxY - edge, width: 2 * edge, height: 2 * edge),
            CGRect(x: panel.maxX - edge, y: panel.maxY - edge, width: 2 * edge, height: 2 * edge)
        ]
        for corner in corners {
            addCursorRect(corner, cursor: .resizeLeftRight)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }

        let point = convert(event.locationInWindow, from: nil)
        let edges = self.edges(at: point)
        guard !edges.isEmpty else { return }

        activeEdges = edges
        startFrame = window.frame
        startScale = max(Theme.minLauncherScale, Theme.launcherScale)
        startPanelHalfWidth = startFrame.width / 2 - Theme.panelInset
        startPanelHalfHeight = startFrame.height / 2 - Theme.panelInset
        startMouse = NSEvent.mouseLocation
        screen = window.screen ?? NSScreen.main
        window.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, !activeEdges.isEmpty, startScale > 0 else { return }

        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - startMouse.x
        let dy = mouse.y - startMouse.y

        let baseWidth = startFrame.width / startScale
        let baseHeight = startFrame.height / startScale
        let basePanelHalfWidth = startPanelHalfWidth / startScale
        let basePanelHalfHeight = startPanelHalfHeight / startScale
        guard baseWidth > 0, baseHeight > 0,
              basePanelHalfWidth > 0, basePanelHalfHeight > 0 else { return }

        // Track the visible panel border under the mouse. The outer window
        // grows symmetrically around the fixed center, so its edge moves
        // slightly faster than the cursor; the panel border stays with it.
        var horizontalScale: CGFloat?
        if activeEdges.contains(.right) {
            horizontalScale = (startPanelHalfWidth + dx) / basePanelHalfWidth
        } else if activeEdges.contains(.left) {
            horizontalScale = (startPanelHalfWidth - dx) / basePanelHalfWidth
        }

        var verticalScale: CGFloat?
        if activeEdges.contains(.top) {
            verticalScale = (startPanelHalfHeight + dy) / basePanelHalfHeight
        } else if activeEdges.contains(.bottom) {
            verticalScale = (startPanelHalfHeight - dy) / basePanelHalfHeight
        }

        let proposed: CGFloat
        switch (horizontalScale, verticalScale) {
        case let (horizontal?, vertical?):
            proposed = abs(horizontal - startScale) >= abs(vertical - startScale)
                ? horizontal
                : vertical
        case let (horizontal?, nil):
            proposed = horizontal
        case let (nil, vertical?):
            proposed = vertical
        default:
            return
        }

        let visible = (screen ?? window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Use the tallest possible content (seven result rows) for the screen
        // limit, so shrinking the list after a large resize cannot push the
        // panel off-screen later.
        let maxContentBaseHeight: CGFloat = 472
        let maxByScreen = min(
            (visible.width - 16) / baseWidth,
            (visible.height - 16) / maxContentBaseHeight
        )
        let maximum = max(Theme.minLauncherScale, min(Theme.maxLauncherScale, maxByScreen))
        let scale = min(max(proposed, Theme.minLauncherScale), maximum)

        onScaleChanged?(scale)

        let size = NSSize(width: baseWidth * scale, height: baseHeight * scale)
        let center = NSPoint(x: startFrame.midX, y: startFrame.midY)
        var frame = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )

        // Keep the panel fully on screen. At sizes that fit, the center is
        // untouched; near the screen edge it slides just enough to stay visible.
        let margin: CGFloat = 8
        frame.origin.x = min(
            max(frame.origin.x, visible.minX + margin),
            visible.maxX - margin - size.width
        )
        frame.origin.y = min(
            max(frame.origin.y, visible.minY + margin),
            visible.maxY - margin - size.height
        )

        window.setFrame(frame.integral, display: true, animate: false)
        window.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard !activeEdges.isEmpty else { return }
        activeEdges = []
        onScaleCommitted?()
    }
}
