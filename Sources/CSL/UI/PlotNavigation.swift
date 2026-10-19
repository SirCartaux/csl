import Foundation

extension PlotViewport {
    /// Pixel deltas follow AppKit's natural scrolling direction, including momentum.
    func panned(dx: Double, dy: Double, pixelWidth: Double, pixelHeight: Double) -> PlotViewport {
        guard pixelWidth > 0, pixelHeight > 0, dx.isFinite, dy.isFinite else { return self }
        let x = dx / pixelWidth * width
        let y = dy / pixelHeight * height
        return PlotViewport(xMin: xMin-x, xMax: xMax-x, yMin: yMin+y, yMax: yMax+y)
    }

    /// Keep the mathematical point under the pointer fixed throughout zooming.
    func zoomed(by factor: Double, anchorX: Double, anchorY: Double) -> PlotViewport? {
        let w = width*factor, h = height*factor
        guard factor.isFinite, w > 1e-9, w < 1e12, h > 1e-12, h < 1e100 else { return nil }
        let x = xMin + anchorX*width, y = yMax-anchorY*height
        let next = PlotViewport(xMin: x+(xMin-x)*factor, xMax: x+(xMax-x)*factor,
                                yMin: y+(yMin-y)*factor, yMax: y+(yMax-y)*factor)
        guard next.xMin.isFinite, next.xMax.isFinite, next.yMin.isFinite, next.yMax.isFinite,
              next.width > 0, next.height > 0 else { return nil }
        return next
    }

    func interpolated(to target: PlotViewport, fraction: Double) -> PlotViewport {
        let t = max(0, min(1, fraction))
        return PlotViewport(xMin: xMin+(target.xMin-xMin)*t, xMax: xMax+(target.xMax-xMax)*t,
                            yMin: yMin+(target.yMin-yMin)*t, yMax: yMax+(target.yMax-yMax)*t)
    }

    func distance(to target: PlotViewport) -> Double {
        max(abs(xMin-target.xMin)/width, abs(xMax-target.xMax)/width,
            abs(yMin-target.yMin)/height, abs(yMax-target.yMax)/height)
    }
}
