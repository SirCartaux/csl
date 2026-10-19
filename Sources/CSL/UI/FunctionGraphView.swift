import AppKit

/// Inline graph using the launcher's existing palette, pixel type and sharp frames.
final class FunctionGraphView: NSView {
    private var function: FunctionExpression?
    private(set) var viewport = PlotViewport()
    private var features: [PlotFeature] = []
    private var curves: [[PlotPoint]] = []
    private var curvePaths: [NSBezierPath] = []
    private var geometryDirty = true
    private var featureWork: DispatchWorkItem?
    private var zoomTarget: PlotViewport?
    private var zoomTimer: Timer?
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()

    deinit { zoomTimer?.invalidate(); featureWork?.cancel() }

    func stopInteraction() {
        zoomTimer?.invalidate(); zoomTimer = nil; zoomTarget = nil
        featureWork?.cancel(); featureWork = nil
        dragOrigin = nil
    }
    private var hover: NSPoint?
    private var dragOrigin: NSPoint?
    private var dragViewport = PlotViewport()
    private var tracking: NSTrackingArea?
    private var autoFit = true
    private var lastPlotSize: CGSize = .zero
    override var isFlipped: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if window == nil { stopInteraction() }
    }

    private var plotRect: CGRect {
        CGRect(x: Theme.ls(64), y: Theme.ls(43), width: max(10, bounds.width-Theme.ls(90)), height: max(10, bounds.height-Theme.ls(103)))
    }
    private var autoRect: CGRect { CGRect(x: bounds.width-Theme.ls(86), y: Theme.ls(12), width: Theme.ls(62), height: Theme.ls(20)) }
    private var minusRect: CGRect { autoRect.offsetBy(dx: -Theme.ls(30), dy: 0).withWidth(24*Theme.launcherScale) }
    private var plusRect: CGRect { minusRect.offsetBy(dx: -Theme.ls(30), dy: 0) }

    func configure(_ raw: String) {
        function = try? FunctionExpression(raw)
        hover = nil
        resetViewport()
        toolTip = "Mouse wheel / pinch: zoom · Two-finger scroll / drag: pan · Enter / AUTO: fit"
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(function.map { "Function graph: y = \($0.source). Mouse wheel or pinch to zoom, two-finger scroll or drag to pan, double click to fit." } ?? "Incomplete function. Example: y=x^2")
    }

    func resetViewport() {
        stopInteraction()
        autoFit = true
        if let function { viewport = FunctionPlot.autoViewport(function) }
        rebuild()
    }
    private func rebuild() {
        geometryDirty = true
        if let function {
            features = FunctionPlot.features(function, from: viewport.xMin, to: viewport.xMax)
        } else { features = [] }
        needsDisplay = true
    }

    private func navigationChanged() {
        autoFit = false
        hover = nil
        geometryDirty = true
        needsDisplay = true
        // Input can arrive more often than frames. Refine roots/extrema only
        // after the gesture settles; existing markers stay in world coordinates.
        featureWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuild() }
        featureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.10, execute: work)
    }

    override func layout() {
        super.layout()
        if lastPlotSize != plotRect.size {
            lastPlotSize = plotRect.size
            geometryDirty = true
            needsDisplay = true
        }
    }

    private func updateGeometryIfNeeded() {
        guard geometryDirty else { return }
        geometryDirty = false
        curves = function.map { FunctionPlot.segments($0, in: viewport, pixelHeight: Double(plotRect.height)) } ?? []
        curvePaths = curves.map { curve in
            let path = NSBezierPath()
            path.move(to: screen(curve[0]))
            for point in curve.dropFirst() { path.line(to: screen(point)) }
            return path
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func resetCursorRects() {
        addCursorRect(plotRect, cursor: .crosshair)
        for rect in [autoRect, plusRect, minusRect] { addCursorRect(rect, cursor: .pointingHand) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hover = plotRect.contains(point) ? point : nil
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if autoRect.contains(point) || (event.clickCount == 2 && plotRect.contains(point)) { resetViewport(); return }
        if plusRect.contains(point) { zoom(0.75, animated: true, at: CGPoint(x: plotRect.midX, y: plotRect.midY)); return }
        if minusRect.contains(point) { zoom(1.333333, animated: true, at: CGPoint(x: plotRect.midX, y: plotRect.midY)); return }
        guard plotRect.contains(point) else { return }
        stopInteraction()
        dragOrigin = point; dragViewport = viewport
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        viewport = dragViewport.panned(dx: Double(point.x-origin.x), dy: Double(point.y-origin.y),
                                       pixelWidth: Double(plotRect.width), pixelHeight: Double(plotRect.height))
        navigationChanged()
    }
    override func mouseUp(with event: NSEvent) { dragOrigin = nil }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard function != nil, plotRect.contains(point) else { return }
        if event.hasPreciseScrollingDeltas {
            // macOS already supplies natural direction and decaying momentum.
            // Follow it 1:1 rather than layering another inertia effect on top.
            stopInteraction()
            viewport = viewport.panned(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                                       pixelWidth: Double(plotRect.width), pixelHeight: Double(plotRect.height))
            navigationChanged()
        } else {
            let delta = Double(event.scrollingDeltaY) * (event.isDirectionInvertedFromDevice ? -1 : 1)
            zoom(exp(max(-0.5, min(0.5, -delta*0.10))), animated: true, at: point)
        }
    }

    func containsPlotPoint(_ point: NSPoint) -> Bool {
        !isHidden && function != nil && plotRect.contains(point)
    }

    /// Called by the root view's native recognizer, independent of field focus.
    func magnify(by amount: CGFloat, at point: NSPoint) {
        guard function != nil, amount.isFinite else { return }
        stopInteraction()
        zoom(1 / max(0.05, 1+Double(amount)), animated: false, at: point)
    }

    private func zoom(_ factor: Double, animated: Bool, at point: NSPoint) {
        guard function != nil else { return }
        let base = zoomTarget ?? viewport
        guard let target = base.zoomed(by: factor,
                                      anchorX: Double((point.x-plotRect.minX)/plotRect.width),
                                      anchorY: Double((point.y-plotRect.minY)/plotRect.height)) else { return }
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stopInteraction()
            viewport = target
            navigationChanged()
            return
        }
        zoomTarget = target
        guard zoomTimer == nil else { return }
        lastFrameTime = CFAbsoluteTimeGetCurrent()
        let fps = max(60, min(120, window?.screen?.maximumFramesPerSecond ?? 60))
        let timer = Timer(timeInterval: 1/Double(fps), repeats: true) { [weak self] timer in
            guard let self, !self.isHidden, self.window?.isVisible == true, let target = self.zoomTarget else {
                timer.invalidate()
                self?.zoomTimer = nil
                self?.zoomTarget = nil
                return
            }
            let now = CFAbsoluteTimeGetCurrent()
            let dt = min(0.05, now-self.lastFrameTime)
            self.lastFrameTime = now
            self.viewport = self.viewport.interpolated(to: target, fraction: 1-exp(-dt/0.045))
            if self.viewport.distance(to: target) < 0.0005 {
                self.viewport = target
                timer.invalidate(); self.zoomTimer = nil; self.zoomTarget = nil
            }
            self.navigationChanged()
        }
        timer.tolerance = 0.001
        zoomTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func screen(_ p: PlotPoint) -> CGPoint {
        CGPoint(x: plotRect.minX + (p.x-viewport.xMin)/viewport.width*plotRect.width,
                y: plotRect.maxY - (p.y-viewport.yMin)/viewport.height*plotRect.height)
    }
    private func label(_ text: String, _ point: CGPoint, color: NSColor = Theme.textDim, size: CGFloat = 9) {
        (text as NSString).draw(at: point, withAttributes: [.font: Theme.launcherDisplay(size), .foregroundColor: color])
    }
    private func number(_ value: Double) -> String {
        let v = abs(value) < 1e-10 ? 0 : value
        return String(format: "%.4g", v).replacingOccurrences(of: ".", with: ",")
    }
    private func line(_ a: CGPoint, _ b: CGPoint, color: NSColor, width: CGFloat = 1) {
        let path = NSBezierPath(); path.move(to: a); path.line(to: b)
        path.lineWidth = width; color.setStroke(); path.stroke()
    }
    private func ticks(_ low: Double, _ high: Double, target: Double) -> [Double] {
        let raw = (high-low)/target
        guard raw.isFinite, raw > 0 else { return [] }
        let unit = pow(10, floor(log10(raw)))
        let step = ([1.0, 2, 5, 10].first { $0*unit >= raw } ?? 10)*unit
        let start = ceil(low/step)*step
        return (0..<20).map { start+Double($0)*step }.filter { $0 <= high }
    }
    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.fill(bounds.insetBy(dx: 1, dy: 0), Theme.bg)
        label("FUNCTION", CGPoint(x: Theme.ls(20), y: Theme.ls(16)), color: Theme.accent, size: 10)
        label("RAD", CGPoint(x: Theme.ls(115), y: Theme.ls(17)), color: Theme.textFaint, size: 8)
        for (rect, text) in [(plusRect, "+"), (minusRect, "-"), (autoRect, "AUTO")] {
            PixelDraw.fill(rect, text == "AUTO" && autoFit ? Theme.accent.withAlphaComponent(0.12) : Theme.bgRaised)
            PixelDraw.frame(rect, thickness: 1, color: text == "AUTO" && autoFit ? Theme.accentDim : Theme.border, notch: Theme.ls(2))
            let size = (text as NSString).size(withAttributes: [.font: Theme.launcherDisplay(9)])
            label(text, CGPoint(x: rect.midX-size.width/2, y: rect.midY-size.height/2), color: Theme.accent)
        }
        guard let function else {
            label("ENTER A FUNCTION", CGPoint(x: Theme.ls(64), y: Theme.ls(90)), color: Theme.text, size: 13)
            label("TRY y=x^2  /  y=sin(x)  /  y=1/x", CGPoint(x: Theme.ls(64), y: Theme.ls(125)))
            label("USE PARENTHESES: sqrt(x), (x+2)^2", CGPoint(x: Theme.ls(64), y: Theme.ls(150)))
            return
        }
        PixelDraw.fill(plotRect, Theme.bgRaised)
        for x in ticks(viewport.xMin, viewport.xMax, target: 7) {
            let sx = screen(PlotPoint(x: x, y: 0)).x
            line(CGPoint(x: sx, y: plotRect.minY), CGPoint(x: sx, y: plotRect.maxY), color: Theme.line)
            let text = number(x)
            let width = (text as NSString).size(withAttributes: [.font: Theme.launcherDisplay(8)]).width
            label(text, CGPoint(x: sx-width/2, y: plotRect.maxY+Theme.ls(7)), size: 8)
        }
        for y in ticks(viewport.yMin, viewport.yMax, target: 5) {
            let sy = screen(PlotPoint(x: 0, y: y)).y
            line(CGPoint(x: plotRect.minX, y: sy), CGPoint(x: plotRect.maxX, y: sy), color: Theme.line)
            let text = number(y)
            let width = (text as NSString).size(withAttributes: [.font: Theme.launcherDisplay(8)]).width
            label(text, CGPoint(x: plotRect.minX-width-Theme.ls(8), y: sy-Theme.ls(5)), size: 8)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plotRect).addClip()
        let origin = screen(PlotPoint(x: 0, y: 0))
        line(CGPoint(x: origin.x, y: plotRect.minY), CGPoint(x: origin.x, y: plotRect.maxY), color: Theme.borderBright)
        line(CGPoint(x: plotRect.minX, y: origin.y), CGPoint(x: plotRect.maxX, y: origin.y), color: Theme.borderBright)
        updateGeometryIfNeeded()
        for path in curvePaths {
            Theme.accent.withAlphaComponent(0.12).setStroke(); path.lineWidth = Theme.ls(7); path.stroke()
            Theme.accent.setStroke(); path.lineWidth = Theme.ls(1.8); path.stroke()
        }
        for feature in features {
            let p = screen(feature.point)
            guard plotRect.contains(p) else { continue }
            PixelDraw.fill(CGRect(x: p.x-Theme.ls(3), y: p.y-Theme.ls(3), width: Theme.ls(6), height: Theme.ls(6)), Theme.success)
        }
        var readout: String?
        if let hover {
            let nearest = features.min { hypot(screen($0.point).x-hover.x, screen($0.point).y-hover.y) < hypot(screen($1.point).x-hover.x, screen($1.point).y-hover.y) }
            let snapped = nearest.flatMap { hypot(screen($0.point).x-hover.x, screen($0.point).y-hover.y) < Theme.ls(18) ? $0 : nil }
            let x = snapped?.point.x ?? (viewport.xMin+Double((hover.x-plotRect.minX)/plotRect.width)*viewport.width)
            let y = function.value(at: x)
            let p = screen(PlotPoint(x: x, y: y))
            line(CGPoint(x: p.x, y: plotRect.minY), CGPoint(x: p.x, y: plotRect.maxY), color: Theme.textFaint)
            if y.isFinite && plotRect.contains(p) {
                PixelDraw.fill(CGRect(x: p.x-Theme.ls(3), y: p.y-Theme.ls(3), width: Theme.ls(6), height: Theme.ls(6)), Theme.text)
            }
            readout = "\(snapped.map { $0.kind.rawValue + "  " } ?? "")x \(number(x))  /  y \(y.isFinite ? number(y) : "UNDEFINED")"
        }
        NSGraphicsContext.restoreGraphicsState()
        PixelDraw.frame(plotRect, thickness: 1, color: Theme.border, notch: 0)
        label("x", CGPoint(x: plotRect.maxX+Theme.ls(8), y: plotRect.maxY+Theme.ls(6)), color: Theme.accent, size: 8)
        label("y", CGPoint(x: plotRect.minX-Theme.ls(15), y: plotRect.minY-Theme.ls(15)), color: Theme.accent, size: 8)
        let summary = features.prefix(3).map { "\($0.kind.rawValue) (\(number($0.point.x)); \(number($0.point.y)))" }.joined(separator: "   ")
        label(readout ?? (curves.isEmpty ? "NO REAL VALUES IN THIS VIEW" : (summary.isEmpty ? "HOVER TO READ COORDINATES" : summary)),
              CGPoint(x: Theme.ls(20), y: bounds.height-Theme.ls(22)), color: readout == nil ? Theme.success : Theme.text, size: 8)
    }
}

private extension CGRect {
    func withWidth(_ width: CGFloat) -> CGRect { CGRect(x: minX, y: minY, width: width, height: height) }
}
