import XCTest
import AppKit
@testable import CSL

@MainActor
final class InteractionMotionTests: XCTestCase {
    private func layers(in layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap { layers(in: $0) }
    }

    func testEffectsNeverInterceptInputAndReuseLayersUnderBurst() throws {
        _ = NSApplication.shared
        let effects = InteractionEffectsView(frame: CGRect(x: 0, y: 0, width: 764, height: 518))
        effects.layoutSubtreeIfNeeded()
        effects.activate()
        let root = try XCTUnwrap(effects.layer)
        let original = layers(in: root).map(ObjectIdentifier.init)
        for i in 0..<1000 {
            let point = CGPoint(x: 100 + i % 300, y: 120 + i % 200)
            effects.pointerMoved(to: point)
            effects.click(at: point)
            effects.inputPulse()
            effects.setSelection(CGRect(x: 40, y: 140 + i % 200, width: 680, height: 42), animated: true)
            XCTAssertNil(effects.hitTest(point))
        }
        XCTAssertEqual(layers(in: root).map(ObjectIdentifier.init), original)
        effects.stop()
        XCTAssertFalse(effects.active)
        XCTAssertTrue(layers(in: root).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        effects.click(at: CGPoint(x: 100, y: 200))
        effects.inputPulse()
        XCTAssertTrue(layers(in: root).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    }

    func testInterruptedPresentationRestoresOpacityAndRemovesAnimations() throws {
        _ = NSApplication.shared
        let controller = SearchViewController()
        _ = controller.view
        controller.preparePixelOpen()
        controller.startPixelOpen()
        controller.cancelPixelAnimations()
        let layer = try XCTUnwrap(controller.view.layer)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertNil(layer.mask)
        XCTAssertNil(layer.animation(forKey: "launcherAppear"))
        XCTAssertNil(layer.animation(forKey: "launcherDisappear"))
        controller.stopGlow()
    }
}
