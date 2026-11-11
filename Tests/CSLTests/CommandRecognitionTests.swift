import XCTest
import AppKit
import QuartzCore
@testable import CSL

@MainActor
final class CommandRecognitionTests: XCTestCase {
    private var oldPreference: MotionPreference = .system
    private let field = CGRect(x: 32, y: 64, width: 700, height: 54)
    private let prefix = CGRect(x: 78, y: 76, width: 86, height: 26)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        PixelFont.registerBundledFonts()
        oldPreference = SettingsStore.shared.motionPreference
        SettingsStore.shared.setMotionPreference(.on)
    }

    override func tearDown() {
        SettingsStore.shared.setMotionPreference(oldPreference)
        super.tearDown()
    }

    private func layers(_ layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(layers)
    }

    private func animations(_ view: NSView) -> [CAAnimation] {
        guard let root = view.layer else { return [] }
        return layers(root).flatMap { layer in
            (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) }
        }
    }

    func testRecognitionRunsOncePerCommandAndReusesLayersWhileTyping() throws {
        let effect = CommandRecognitionView(frame: CGRect(x: 0, y: 0, width: 764, height: 390))
        let root = try XCTUnwrap(effect.layer)
        let original = layers(root).map(ObjectIdentifier.init)
        let stop = try XCTUnwrap(InlineCommand.parse("stop", shortcuts: []))
        effect.update(command: stop, prefixRect: prefix, fieldRect: field, animated: true)
        let badge = try XCTUnwrap(layers(root).first { $0.animation(forKey: "commandRecognized") != nil })
        let first = try XCTUnwrap(badge.animation(forKey: "commandRecognized"))
        XCTAssertEqual(animations(effect).count, 3)
        for i in 0..<1000 {
            let command = InlineCommand.parse("StOp Safari \(i)", shortcuts: [])
            effect.update(command: command, prefixRect: prefix, fieldRect: field, animated: true)
        }
        XCTAssertEqual(badge.animation(forKey: "commandRecognized")?.beginTime, first.beginTime,
                       "Argument edits must not restart the recognition animation")
        XCTAssertEqual(layers(root).map(ObjectIdentifier.init), original)
        XCTAssertNil(effect.hitTest(prefix.origin))
        for animation in animations(effect) {
            XCTAssertLessThanOrEqual(animation.duration, 0.7)
            XCTAssertEqual(animation.repeatCount, 0)
            XCTAssertTrue(animation.isRemovedOnCompletion)
        }
        XCTAssertEqual(badge.opacity, 0, "The resting layer must remain invisible after the finite animation")
        effect.update(command: InlineCommand.parse("restart Safari", shortcuts: []), prefixRect: prefix, fieldRect: field, animated: true)
        XCTAssertEqual(effect.recognizedID, "process:restart")
        XCTAssertEqual(animations(effect).count, 3)
        effect.stop()
        XCTAssertNil(effect.recognizedID)
        XCTAssertTrue(animations(effect).isEmpty)
    }

    func testMotionOffHiddenInputAndLeavingCommandModeCancelEffects() throws {
        let effect = CommandRecognitionView(frame: CGRect(x: 0, y: 0, width: 764, height: 390))
        let stop = InlineCommand.parse("stop", shortcuts: [])
        effect.update(command: stop, prefixRect: prefix, fieldRect: field, animated: true)
        XCTAssertFalse(animations(effect).isEmpty)
        SettingsStore.shared.setMotionPreference(.off)
        effect.update(command: stop, prefixRect: prefix, fieldRect: field, animated: true)
        XCTAssertTrue(animations(effect).isEmpty)
        SettingsStore.shared.setMotionPreference(.on)
        effect.stop()
        effect.update(command: stop, prefixRect: prefix, fieldRect: field, animated: false)
        XCTAssertTrue(animations(effect).isEmpty)
        effect.update(command: nil, prefixRect: .null, fieldRect: field, animated: true)
        XCTAssertNil(effect.recognizedID)
        effect.update(command: stop, prefixRect: .null, fieldRect: field, animated: true)
        XCTAssertTrue(animations(effect).isEmpty, "A scrolled-out prefix must not flash elsewhere")
    }

    func testClosingLauncherAndClipboardModeStopRecognition() throws {
        let controller = SearchViewController()
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 764, height: 390),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.orderOut(nil); controller.stopGlow() }
        window.orderFront(nil)
        controller.view.layoutSubtreeIfNeeded()
        controller.focus()
        controller.setSearchText("restart")
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(animations(controller.commandRecognition).isEmpty,
                       "Typing a prefix in the actual visible launcher must attach the effect")
        let before = animations(controller.commandRecognition).first { $0.duration == 0.56 }?.beginTime
        controller.setSearchText("ReStArT Safari")
        XCTAssertEqual(animations(controller.commandRecognition).first { $0.duration == 0.56 }?.beginTime, before)
        controller.setSearchText("Safari")
        XCTAssertTrue(animations(controller.commandRecognition).isEmpty)
        controller.setSearchText("stop")
        XCTAssertFalse(animations(controller.commandRecognition).isEmpty)
        controller.stopGlow()
        XCTAssertTrue(animations(controller.commandRecognition).isEmpty)
        controller.setSearchText("restart")
        XCTAssertFalse(animations(controller.commandRecognition).isEmpty)
        controller.enterClipboardMode()
        XCTAssertTrue(animations(controller.commandRecognition).isEmpty)
        XCTAssertNil(controller.commandRecognition.recognizedID)
    }

    func testExistingPromptAndHaloRespectMotionOffWithoutIdleLoops() throws {
        let prompt = SearchPromptView(frame: CGRect(x: 0, y: 0, width: 20, height: 24))
        let halo = GlowView(frame: CGRect(x: 0, y: 0, width: 764, height: 390))
        prompt.pulse()
        halo.startPulse()
        XCTAssertFalse(animations(prompt).isEmpty)
        XCTAssertFalse(animations(halo).isEmpty)
        XCTAssertTrue((animations(prompt) + animations(halo)).allSatisfy { $0.repeatCount == 0 })
        SettingsStore.shared.setMotionPreference(.off)
        prompt.pulse()
        halo.startPulse()
        XCTAssertTrue(animations(prompt).isEmpty)
        XCTAssertTrue(animations(halo).isEmpty)
    }

    func testNativePrefixGeometryAndVisualSnapshots() throws {
        PixelFont.registerBundledFonts()
        let controller = SearchViewController()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 764, height: 390),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.orderOut(nil); controller.stopGlow() }
        controller.view.layoutSubtreeIfNeeded()
        controller.setSearchText("  ReStArT Safari")
        controller.focus()
        let editor = try XCTUnwrap(controller.searchField.currentEditor() as? NSTextView)
        let selection = editor.selectedRange
        let rect = controller.searchField.inlinePrefixRect()
        XCTAssertFalse(rect.isNull)
        XCTAssertGreaterThan(rect.width, 10)
        XCTAssertTrue(controller.searchField.bounds.contains(rect))
        XCTAssertEqual(editor.selectedRange, selection)
        controller.setSearchText("restart " + String(repeating: "longquery ", count: 200))
        editor.scrollRangeToVisible(NSRange(location: (editor.string as NSString).length, length: 0))
        let scrolled = controller.searchField.inlinePrefixRect()
        XCTAssertTrue(scrolled.isNull || controller.searchField.bounds.contains(scrolled))

        guard let output = ProcessInfo.processInfo.environment["CSL_COMMAND_SNAPSHOT_DIR"] else { return }
        let shortcut = SearchShortcut(id: UUID(), prefix: "KL", name: "Kleinanzeigen",
            searchTemplate: "https://www.kleinanzeigen.de/s-{query}/k0", siteURL: "https://www.kleinanzeigen.de",
            tintHex: "#9BD450", iconFileName: nil)
        let examples = [("stop", "stop"), ("restart Safari", "restart"),
                        ("G Summer in Berlin", "google"), ("KL Kamera", "custom")]
        for (query, filename) in examples {
            controller.setSearchText(query)
            let command = try XCTUnwrap(InlineCommand.parse(query, shortcuts: [shortcut] + ShortcutStore.shared.shortcuts))
            controller.searchField.inlineCommand = command
            (controller.view as? RootView)?.inlineCommand = command
            let names = command.processCommand == .stop ? ["Safari", "Visual Studio Code", "Mail"] :
                [command.processCommand != nil ? "Safari" : command.contextLabel.replacingOccurrences(of: "WEB SEARCH / ", with: "")]
            let results = names.enumerated().map { index, name in
                SearchResult(id: "preview-\(index)", title: name, subtitle: command.query.isEmpty ? "RUNNING APP" : command.query,
                    kind: .command, icon: .glyph(command.processCommand != nil ? .gear : .globe), score: 0,
                    titleMatch: [], action: .run {}, shortcut: ShortcutPresentation(
                        prefix: (query.split(separator: " ").first.map(String.init) ?? "").uppercased(),
                        name: name, tint: command.tint))
            }
            controller.apply(results: results, isSearching: false)
            controller.view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
            controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename + "-smooth.png"))
        }
    }
}
