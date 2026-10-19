import Foundation

struct PlotPoint: Equatable {
    let x: Double
    let y: Double
}
struct PlotFeature {
    enum Kind: String { case root = "ZERO", minimum = "MIN", maximum = "MAX" }
    let point: PlotPoint
    let kind: Kind
}
struct PlotViewport {
    var xMin: Double = -5
    var xMax: Double = 5
    var yMin: Double = -2
    var yMax: Double = 10
    var width: Double { xMax - xMin }
    var height: Double { yMax - yMin }
}

/// Numerical exploration is deliberately bounded. AUTO fits the sampled region,
/// not a claim to discover every feature of an arbitrary mathematical function.
enum FunctionPlot {
    static func features(_ f: FunctionExpression, from lo: Double, to hi: Double, count: Int = 800) -> [PlotFeature] {
        let step = (hi - lo) / Double(count)
        let points = (0...count).map { i -> PlotPoint in
            let x = lo + Double(i) * step
            return PlotPoint(x: x, y: f.value(at: x))
        }
        var result: [PlotFeature] = []
        func append(_ x: Double, _ kind: PlotFeature.Kind) {
            let y = f.value(at: x)
            guard y.isFinite, abs(y) < 1e100 else { return }
            if !result.contains(where: { $0.kind == kind && abs($0.point.x - x) < step * 0.2 }) {
                result.append(PlotFeature(point: PlotPoint(x: x, y: y), kind: kind))
            }
        }
        for i in 1..<count {
            let a = points[i-1], b = points[i], c = points[i+1]
            guard a.y.isFinite, b.y.isFinite, c.y.isFinite else { continue }
            if b.y == 0 && (a.y != 0 || c.y != 0) { append(b.x, .root) }
            if (a.y < 0 && b.y > 0) || (a.y > 0 && b.y < 0) {
                var l = a.x, r = b.x, yl = a.y
                for _ in 0..<50 {
                    let m = (l + r) / 2, y = f.value(at: m)
                    if !y.isFinite { break }
                    if (yl < 0) == (y < 0) { l = m; yl = y } else { r = m }
                }
                let x = (l + r) / 2, y = f.value(at: x)
                // A sign change across a pole is not a root.
                if abs(y) < 1e-7 * max(1, min(abs(a.y), abs(b.y))) { append(x, .root) }
            }
            let isMin = b.y < a.y && b.y <= c.y
            let isMax = b.y > a.y && b.y >= c.y
            if isMin || isMax {
                var l = a.x, r = c.x
                for _ in 0..<48 {
                    let p = l + (r-l)/3, q = r - (r-l)/3
                    let yp = f.value(at: p), yq = f.value(at: q)
                    if (yp < yq) == isMin { r = q } else { l = p }
                }
                let x = (l+r)/2, y = f.value(at: x)
                let near = step * 0.001
                let left = f.value(at: x-near), right = f.value(at: x+near)
                let tolerance = max(1, abs(y)) * 0.01
                if y.isFinite, abs(left-y) < tolerance, abs(right-y) < tolerance {
                    append(x, isMin ? .minimum : .maximum)
                    if abs(y) < 1e-9, abs(a.y) > 1e-8 || abs(c.y) > 1e-8 { append(x, .root) }
                }
            }
        }
        return result.sorted { $0.point.x < $1.point.x }
    }

    static func autoViewport(_ f: FunctionExpression) -> PlotViewport {
        var view = PlotViewport()
        var found = features(f, from: -5, to: 5)
        if found.count <= 4 {
            for radius in [50.0, 500.0, 5000.0] {
                let broad = features(f, from: -radius, to: radius, count: 1200)
                if broad.isEmpty { continue }
                guard broad.count <= 8 else { break }
                let outside = broad.filter { abs($0.point.x) > 4.5 }
                if !outside.isEmpty, broad.count > found.count || found.isEmpty {
                    found = broad
                    let xs = found.map { $0.point.x }
                    let low = xs.min()!, high = xs.max()!
                    let pad = max(3, (high-low) * 0.25)
                    view.xMin = low-pad
                    view.xMax = high+pad
                    break
                }
            }
        }
        if !found.isEmpty && found.count <= 4 {
            let xs = found.map { $0.point.x }
            let low = xs.min()!, high = xs.max()!
            let pad = max(2, (high-low)*0.25)
            view.xMin = low-pad; view.xMax = high+pad
        }
        var ys = (0...1000).map { i in
            f.value(at: view.xMin + view.width * Double(i)/1000)
        }.filter { $0.isFinite && abs($0) < 1e100 }.sorted()
        if ys.isEmpty {
            // Locate shifted domains, e.g. sqrt(x-100), without inventing values.
            for center in [10.0, -10, 100, -100, 1000, -1000] {
                let values = (0...100).map { f.value(at: center - 5 + Double($0)/10) }.filter { $0.isFinite && abs($0) < 1e100 }.sorted()
                if !values.isEmpty { view.xMin = center-5; view.xMax = center+5; ys = values; break }
            }
        }
        guard !ys.isEmpty else { return view }
        // Trim pole/exp tails while retaining the interesting central curve.
        var low = ys[Int(Double(ys.count-1)*0.04)]
        var high = ys[Int(Double(ys.count-1)*0.96)]
        let visibleFeatures = features(f, from: view.xMin, to: view.xMax)
        for feature in visibleFeatures {
            low = min(low, feature.point.y); high = max(high, feature.point.y)
        }
        if high-low < max(1e-12, abs(high)*1e-12) {
            let pad = max(1, abs(high)*0.1)
            low -= pad; high += pad
        }
        let span = high-low
        if low > 0 && low < span*0.3 { low = 0 }
        if high < 0 && -high < span*0.3 { high = 0 }
        let pad = (high-low)*0.12
        view.yMin = low-pad; view.yMax = high+pad
        return view
    }

    /// Adaptive midpoint checks split curves at poles, undefined domains and jumps.
    static func segments(_ f: FunctionExpression, in v: PlotViewport, pixelHeight: Double) -> [[PlotPoint]] {
        var segments: [[PlotPoint]] = []
        var current: [PlotPoint] = []
        func flush() { if current.count > 1 { segments.append(current) }; current = [] }
        func visit(_ a: PlotPoint, _ b: PlotPoint, _ depth: Int) {
            let m = PlotPoint(x: (a.x+b.x)/2, y: f.value(at: (a.x+b.x)/2))
            let valid = a.y.isFinite && b.y.isFinite && m.y.isFinite
            let error = valid ? abs(m.y - (a.y/2+b.y/2)) / v.height * pixelHeight : .infinity
            let jump = valid ? abs(b.y-a.y)/v.height*pixelHeight : .infinity
            if depth < 8 && (!valid || error > 0.7 || jump > pixelHeight*0.5) {
                // Do not recurse through large wholly undefined/offscreen regions.
                if !a.y.isFinite && !b.y.isFinite && !m.y.isFinite { flush(); return }
                if valid && ((a.y > v.yMax && b.y > v.yMax && m.y > v.yMax) || (a.y < v.yMin && b.y < v.yMin && m.y < v.yMin)) { flush(); return }
                visit(a, m, depth+1); visit(m, b, depth+1); return
            }
            guard valid, error <= 2, jump < pixelHeight*0.8,
                  a.y >= v.yMin-v.height, a.y <= v.yMax+v.height,
                  b.y >= v.yMin-v.height, b.y <= v.yMax+v.height else { flush(); return }
            if current.isEmpty { current.append(a) }
            current.append(b)
        }
        let count = 600
        var a = PlotPoint(x: v.xMin, y: f.value(at: v.xMin))
        for i in 1...count {
            let x = v.xMin + v.width * Double(i)/Double(count)
            let b = PlotPoint(x: x, y: f.value(at: x))
            visit(a,b,0); a = b
        }
        flush()
        return segments
    }
}
