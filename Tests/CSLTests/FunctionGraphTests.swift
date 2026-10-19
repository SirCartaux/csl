import XCTest
import AppKit
@testable import CSL

final class FunctionGraphTests: XCTestCase {
    func testExpressions() throws {
        for (input, x, expected) in [
            ("y=x^2", 3.0, 9.0), ("f(x)=-x^2+2x+1", 3, -2),
            ("y=2^3^2", 0, 512), ("y=x(x+1)", 2, 6),
            ("y=sin(pi/2)+cos(0)", 0, 2), ("y=sqrt(x)", 4, 2),
            ("y=1,5x", 2, 3), ("y=(1,5*x)^2", 2, 9),
            ("y=log2(x)", 8, 3), ("y=pow(x;2)", 3, 9),
            ("y=1e-3*x", 2, 0.002), ("y=x²", 3, 9), ("2x+1", 2, 5)
        ] {
            XCTAssertEqual(try FunctionExpression(input).value(at: x), expected, accuracy: 1e-9, input)
        }
        for input in ["y=", "y=sin(", "y=foo(x)", "y=x+", "y=x=2", "y=sin(x;2)", "y="+String(repeating: "(", count: 65)+"x"+String(repeating: ")", count: 65)] {
            XCTAssertThrowsError(try FunctionExpression(input), input)
        }
        for query in ["Xcode", "example.txt", "hello", "2+2", "xcode.app"] { XCTAssertNil(FunctionExpression.body(of: query)) }
        XCTAssertFalse(try FunctionExpression("y=sqrt(x)").value(at: -1).isFinite)
    }

    func testAutomaticFraming() throws {
        for (input, points) in [
            ("y=x^2", [PlotPoint(x:0,y:0)]),
            ("y=x^2-100", [PlotPoint(x:-10,y:0), PlotPoint(x:10,y:0), PlotPoint(x:0,y:-100)]),
            ("y=(x-100)^2+10", [PlotPoint(x:100,y:10)]),
            ("y=1000000*x^2", [PlotPoint(x:0,y:0)]),
            ("y=0.000001*x^2", [PlotPoint(x:0,y:0)]),
            ("y=42", [PlotPoint(x:0,y:42)]),
            ("y=sin(x)", [PlotPoint(x:Double.pi/2,y:1), PlotPoint(x:-Double.pi/2,y:-1)])
        ] {
            let f = try FunctionExpression(input), v = FunctionPlot.autoViewport(f)
            XCTAssertTrue(v.width.isFinite && v.height.isFinite && v.width > 0 && v.height > 0, input)
            for p in points {
                XCTAssertTrue((v.xMin...v.xMax).contains(p.x) && (v.yMin...v.yMax).contains(p.y), "\(input): \(p) outside \(v)")
            }
        }
        let domain = try FunctionExpression("y=sqrt(x-100)")
        XCTAssertFalse(FunctionPlot.segments(domain, in: FunctionPlot.autoViewport(domain), pixelHeight: 240).isEmpty)
    }

    func testFeaturesAndDiscontinuities() throws {
        let parabola = try FunctionExpression("y=(x-2)^2-4")
        let features = FunctionPlot.features(parabola, from: -5, to: 5)
        XCTAssertTrue(features.contains { $0.kind == .minimum && abs($0.point.x-2) < 1e-6 && abs($0.point.y+4) < 1e-8 })
        for root in [0.0,4] { XCTAssertTrue(features.contains { $0.kind == .root && abs($0.point.x-root) < 1e-6 }) }
        for input in ["y=1/x", "y=1/(x-0.123)", "y=tan(x)"] {
            let f = try FunctionExpression(input)
            let v = FunctionPlot.autoViewport(f)
            let segments = FunctionPlot.segments(f, in: v, pixelHeight: 240)
            XCTAssertFalse(segments.isEmpty, input)
            if input.contains("1/") {
                XCTAssertFalse(FunctionPlot.features(f, from: -5, to:5).contains { $0.kind == .root }, input)
                let pole = input.contains("0.123") ? 0.123 : 0
                XCTAssertFalse(segments.contains { $0.first!.x < pole && $0.last!.x > pole }, input)
            }
            XCTAssertLessThan(v.height, 1000, "Pole distorts scale: \(input)")
        }
        let invalid = try FunctionExpression("y=sqrt(-1)")
        XCTAssertTrue(FunctionPlot.segments(invalid, in: FunctionPlot.autoViewport(invalid), pixelHeight: 240).isEmpty)
    }

    @MainActor
    func testLauncherGraphModeRoundTrip() {
        _ = NSApplication.shared
        PixelFont.registerBundledFonts()
        let controller = SearchViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 764, height: 518)
        let root = controller.view as! RootView
        controller.setSearchText("y=x^2")
        XCTAssertTrue(root.graphActive)
        XCTAssertFalse(root.calculatorActive)
        XCTAssertEqual(controller.preferredContentHeight, 454)
        // Late search callbacks must not replace the graph.
        controller.apply(results: [], isSearching: true)
        XCTAssertFalse(root.isSearching)
        controller.setSearchText("y=sin(")
        XCTAssertTrue(root.graphActive)
        controller.setSearchText("2+2")
        XCTAssertFalse(root.graphActive)
        XCTAssertTrue(controller.view.subviews.first { $0 is FunctionGraphView }!.isHidden)
        controller.setSearchText("y=1/x")
        controller.prepareForPresentation()
        XCTAssertFalse(root.graphActive)
        XCTAssertEqual(controller.searchField.stringValue, "")
        XCTAssertFalse(controller.view.subviews.first { $0 is NSScrollView }!.isHidden)
    }

    func testCalculatorStillWorks() {
        XCTAssertEqual(Calculator.evaluate("2+2")?.value, 4)
        XCTAssertEqual(Calculator.evaluate("sin(pi/2)")?.value, 1)
        XCTAssertNil(Calculator.evaluate("y=x^2"))
    }
}
