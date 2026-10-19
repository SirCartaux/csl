import XCTest
import AppKit
@testable import CSL

final class PlotNavigationTests: XCTestCase {
    func testZoomAnchorAndRoundTrip() throws {
        let original = PlotViewport(xMin: -4, xMax: 6, yMin: -10, yMax: 30)
        for (ax, ay) in [(0.0,0.0), (0.23,0.78), (0.5,0.5), (1.0,1.0)] {
            let zoomed = try XCTUnwrap(original.zoomed(by: 0.7, anchorX: ax, anchorY: ay))
            XCTAssertEqual(original.xMin+ax*original.width, zoomed.xMin+ax*zoomed.width, accuracy: 1e-10)
            XCTAssertEqual(original.yMax-ay*original.height, zoomed.yMax-ay*zoomed.height, accuracy: 1e-10)
            let restored = try XCTUnwrap(zoomed.zoomed(by: 1/0.7, anchorX: ax, anchorY: ay))
            XCTAssertLessThan(original.distance(to: restored), 1e-10)
        }
    }

    func testTwoFingerPanIsOneToOneAndKeepsScale() {
        let view = PlotViewport(xMin: -5, xMax: 5, yMin: -10, yMax: 10)
        let moved = view.panned(dx: 100, dy: -50, pixelWidth: 1000, pixelHeight: 500)
        XCTAssertEqual(moved.xMin, -6)
        XCTAssertEqual(moved.yMin, -12)
        XCTAssertEqual(moved.width, view.width)
        XCTAssertEqual(moved.height, view.height)
        let restored = moved.panned(dx: -100, dy: 50, pixelWidth: 1000, pixelHeight: 500)
        XCTAssertLessThan(view.distance(to: restored), 1e-10)
    }

    func testWheelEasingIsFrameRateIndependent() throws {
        let original = PlotViewport()
        let target = try XCTUnwrap(original.zoomed(by: 0.5, anchorX: 0.25, anchorY: 0.7))
        var endings: [PlotViewport] = []
        for fps in [60,120] {
            var current = original
            for _ in 0..<(fps/2) {
                let previousDistance = current.distance(to: target)
                current = current.interpolated(to: target, fraction: 1-exp(-1/Double(fps)/0.045))
                XCTAssertLessThan(current.distance(to: target), previousDistance)
                XCTAssertEqual(current.xMin+0.25*current.width, original.xMin+0.25*original.width, accuracy: 1e-10)
            }
            XCTAssertLessThan(current.distance(to: target), 0.0001)
            endings.append(current)
        }
        XCTAssertLessThan(endings[0].distance(to: endings[1]), 1e-10)
        for invalid in [0.0, -1, Double.infinity, Double.nan, 1e30, 1e-30] {
            XCTAssertNil(original.zoomed(by: invalid, anchorX: 0.5, anchorY: 0.5))
        }
    }
}

@MainActor
final class PinchIntegrationTests: XCTestCase {
    func testNativeRecognizerIsInstalledAboveGraphAndPreservesFieldFocus() throws {
        _ = NSApplication.shared
        let controller = SearchViewController()
        let window = SearchPanel()
        window.contentViewController = controller
        window.setContentSize(CGSize(width:764,height:518))
        controller.setSearchText("y=x^2")
        controller.view.layoutSubtreeIfNeeded()
        window.makeFirstResponder(controller.searchField)
        let focus = window.firstResponder
        let pinch = try XCTUnwrap(controller.view.gestureRecognizers.first as? NSMagnificationGestureRecognizer)
        XCTAssertTrue(pinch.delaysMagnificationEvents)
        XCTAssertNotNil(pinch.target)
        XCTAssertNotNil(pinch.action)
        XCTAssertTrue(controller.view.allowedTouchTypes.contains(.indirect))
        let graph = try XCTUnwrap(controller.view.subviews.first { $0 is FunctionGraphView } as? FunctionGraphView)
        let before = graph.viewport
        final class PinchSample: NSMagnificationGestureRecognizer {
            override var state: NSGestureRecognizer.State { get { .changed } set {} }
            override func location(in view: NSView?) -> NSPoint { CGPoint(x:300,y:150) }
        }
        let sample = PinchSample(target: pinch.target, action: pinch.action)
        sample.magnification = 0.25
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(sample.action), to: sample.target, from: sample))
        XCTAssertEqual(sample.magnification, 0)
        XCTAssertEqual(graph.viewport.width, before.width/1.25, accuracy: 1e-10)
        XCTAssertTrue(window.firstResponder === focus)
        graph.stopInteraction()
    }
}
