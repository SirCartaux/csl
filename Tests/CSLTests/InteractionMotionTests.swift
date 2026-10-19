import XCTest
import AppKit
@testable import CSL

@MainActor
final class InteractionMotionTests: XCTestCase {
    private var previousPreference: MotionPreference = .system

    override func setUp() {
        super.setUp()
        previousPreference = SettingsStore.shared.motionPreference
        SettingsStore.shared.setMotionPreference(.on)
    }

    override func tearDown() {
        SettingsStore.shared.setMotionPreference(previousPreference)
        super.tearDown()
    }

    func testMotionPolicyHonorsExplicitAppChoice() throws {
        XCTAssertFalse(MotionPreference.system.allowsAnimation(reduceMotion: true))
        XCTAssertTrue(MotionPreference.system.allowsAnimation(reduceMotion: false))
        XCTAssertTrue(MotionPreference.on.allowsAnimation(reduceMotion: true))
        XCTAssertTrue(MotionPreference.on.allowsAnimation(reduceMotion: false))
        XCTAssertFalse(MotionPreference.off.allowsAnimation(reduceMotion: true))
        XCTAssertFalse(MotionPreference.off.allowsAnimation(reduceMotion: false))
        let encoded = try JSONEncoder().encode(SettingsStore.shared.settings)
        XCTAssertEqual(try JSONDecoder().decode(CSLSettings.self, from: encoded).motionPreference, .on)
        XCTAssertTrue(InteractionMotion.enabled, "Explicit CSL preference must override this Mac's Reduce Motion setting")
    }

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
        let animated = layers(in: root)
        XCTAssertTrue(animated.contains { $0.animation(forKey: "inputPulse") != nil })
        XCTAssertEqual(animated.filter { $0.animation(forKey: "clickImpulse") != nil }.count, 4)
        XCTAssertTrue(animated.contains { $0.opacity == 1 && $0.bounds.width == Theme.ls(260) })
        effects.stop()
        XCTAssertFalse(effects.active)
        XCTAssertTrue(layers(in: root).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        effects.click(at: CGPoint(x: 100, y: 200))
        effects.inputPulse()
        XCTAssertTrue(layers(in: root).allSatisfy { ($0.animationKeys() ?? []).isEmpty })
    }

    func testVisiblePresentationAdvancesAndReducedMotionRetainsHover() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 764, height: 518),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.orderOut(nil) }
        let effects = InteractionEffectsView(frame: CGRect(x: 0, y: 0, width: 764, height: 518))
        window.contentView = effects
        window.orderFront(nil)
        effects.layoutSubtreeIfNeeded()
        effects.activate()
        effects.pointerMoved(to: CGPoint(x: 150, y: 160))
        effects.inputPulse()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        let all = layers(in: try XCTUnwrap(effects.layer))
        let input = try XCTUnwrap(all.first { $0.animation(forKey: "inputPulse") != nil })
        XCTAssertGreaterThan(input.bounds.width, 100)
        XCTAssertGreaterThan(try XCTUnwrap(input.presentation()).opacity, 0.1)
        effects.stop()
        SettingsStore.shared.setMotionPreference(.off)
        effects.activate()
        effects.setHover(CGRect(x: 40, y: 140, width: 680, height: 42))
        XCTAssertTrue(all.contains { $0.borderWidth > 0 && $0.opacity == 1 })
        XCTAssertTrue(all.allSatisfy { ($0.animationKeys() ?? []).isEmpty })
        effects.stop()
    }

    func testInterruptedPresentationRestoresOpacityAndRemovesAnimations() throws {
        _ = NSApplication.shared
        let controller = SearchViewController()
        _ = controller.view
        controller.preparePixelOpen()
        controller.startPixelOpen()
        XCTAssertNotNil(controller.view.layer?.animation(forKey: "launcherAppear"))
        controller.cancelPixelAnimations()
        let layer = try XCTUnwrap(controller.view.layer)
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertNil(layer.mask)
        XCTAssertNil(layer.animation(forKey: "launcherAppear"))
        XCTAssertNil(layer.animation(forKey: "launcherDisappear"))
        controller.stopGlow()
    }
}
