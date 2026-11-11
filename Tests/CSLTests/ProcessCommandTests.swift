import XCTest
import AppKit
@testable import CSL

@MainActor
final class ProcessCommandTests: XCTestCase {
    private let apps = [
        RunningProgram(processID: 42, name: "Safari", bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")),
        RunningProgram(processID: 43, name: "Visual Studio Code", bundleURL: URL(fileURLWithPath: "/Applications/Code.app")),
        RunningProgram(processID: 44, name: "Code", bundleURL: URL(fileURLWithPath: "/Applications/Other.app"))
    ]

    func testCommandBoundariesAndPrefixRanges() throws {
        for value in ["stop", "STOP ", "sToP Safari", " Restart\tVisual Studio Code "] {
            XCTAssertNotNil(InlineCommand.parse(value, shortcuts: [])?.processCommand, value)
        }
        for value in ["stopping", "restartable Safari", "stopSafari", "how to stop Safari"] {
            XCTAssertNil(InlineCommand.parse(value, shortcuts: []), value)
        }
        let value = "  ReStArT  Größe 🐈"
        let command = try XCTUnwrap(InlineCommand.parse(value, shortcuts: []))
        XCTAssertEqual((value as NSString).substring(with: command.prefixRange), "ReStArT")
        XCTAssertEqual(command.query, "Größe 🐈")
        XCTAssertEqual(command.processCommand, .restart)
    }

    func testCustomPrefixesAndEmptyQueryStayInCommandMode() throws {
        let shortcut = SearchShortcut(id: UUID(), prefix: "KL", name: "Kleinanzeigen",
            searchTemplate: "https://www.kleinanzeigen.de/s-{query}/k0", siteURL: "https://www.kleinanzeigen.de",
            tintHex: "#34A853", iconFileName: nil)
        for value in ["kl ", "KL Kamera"] {
            let inline = try XCTUnwrap(InlineCommand.parse(value, shortcuts: [shortcut]))
            guard case .shortcut(let matched) = inline.kind else { return XCTFail("Expected shortcut") }
            XCTAssertEqual(matched.id, shortcut.id)
        }
        XCTAssertNil(InlineCommand.parse("kl", shortcuts: [shortcut]))
        XCTAssertNotNil(InlineCommand.parse("google ", shortcuts: []))
    }

    func testProviderIsDormantCachesTypingAndReleasesItsObservers() {
        var snapshots = 0
        let center = NotificationCenter()
        let provider = RunningApplicationProvider(snapshot: { snapshots += 1; return self.apps }, center: center)
        XCTAssertFalse(provider.isActive)
        XCTAssertEqual(snapshots, 0)
        XCTAssertEqual(provider.results(command: .stop, query: "").count, 3)
        XCTAssertEqual(provider.results(command: .restart, query: "code").first?.title, "Code")
        XCTAssertEqual(snapshots, 1, "Typing must only filter the cached list")
        var changes = 0
        provider.onChange = { changes += 1 }
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        XCTAssertEqual(snapshots, 2)
        XCTAssertEqual(changes, 1)
        provider.stop()
        center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        XCTAssertEqual(snapshots, 2)
        XCTAssertFalse(provider.isActive)
        XCTAssertTrue(provider.results(command: .stop, query: "no such app").isEmpty)
        XCTAssertEqual(snapshots, 3)
        provider.stop()
    }

    func testEngineKeepsProcessResultsExclusiveAndNeverWarmsThemWhileIdle() {
        final class Delegate: SearchEngineDelegate {
            var results: [SearchResult] = []
            var searching = true
            func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool) {
                self.results = results; searching = isSearching
            }
        }
        var snapshots = 0
        let provider = RunningApplicationProvider(snapshot: { snapshots += 1; return self.apps }, center: NotificationCenter())
        let engine = SearchEngine(processProvider: provider), delegate = Delegate()
        engine.delegate = delegate
        engine.search("")
        XCTAssertEqual(snapshots, 0)
        engine.search("StOp")
        XCTAssertEqual(delegate.results.count, 3)
        XCTAssertFalse(delegate.searching)
        engine.refreshIndexResults()
        engine.search("restart code")
        XCTAssertEqual(delegate.results.first?.title, "Code")
        XCTAssertTrue(delegate.results.allSatisfy { $0.id.hasPrefix("process:restart:") })
        XCTAssertEqual(snapshots, 1)
        engine.search("g ")
        XCTAssertTrue(delegate.results.isEmpty)
        XCTAssertFalse(delegate.searching)
        XCTAssertFalse(provider.isActive)
        engine.search("STOP no such program")
        XCTAssertTrue(delegate.results.isEmpty)
        engine.cancel()
        XCTAssertFalse(provider.isActive)
    }

    func testTabCyclesAndEnterExecutesSelectedProgramWithoutGraphMode() throws {
        _ = NSApplication.shared
        let provider = RunningApplicationProvider(snapshot: { self.apps }, center: NotificationCenter())
        let engine = SearchEngine(processProvider: provider)
        let controller = SearchViewController()
        controller.engine = engine
        _ = controller.view
        final class Delegate: SearchEngineDelegate {
            let controller: SearchViewController
            init(_ controller: SearchViewController) { self.controller = controller }
            func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool) {
                MainActor.assumeIsolated { controller.apply(results: results, isSearching: isSearching) }
            }
        }
        let delegate = Delegate(controller)
        engine.delegate = delegate
        controller.setSearchText("restart")
        var selected: [String] = []
        controller.onChoose = { result, _ in selected.append(result.title) }
        let editor = NSTextView()
        func press(_ selector: Selector) { _ = controller.control(controller.searchField, textView: editor, doCommandBy: selector) }
        press(#selector(NSResponder.insertNewline(_:)))
        press(#selector(NSResponder.insertTab(_:)))
        press(#selector(NSResponder.insertNewline(_:)))
        press(#selector(NSResponder.insertBacktab(_:)))
        press(#selector(NSResponder.insertNewline(_:)))
        press(#selector(NSResponder.insertBacktab(_:)))
        press(#selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(selected, ["Code", "Safari", "Code", "Visual Studio Code"])
        controller.setSearchText("restart x")
        XCTAssertFalse((controller.view as! RootView).graphActive)
        controller.stopGlow()
        engine.cancel()
    }

    func testInlineStylingPreservesEditableTextAndResetsSuffix() throws {
        _ = NSApplication.shared
        let controller = SearchViewController()
        _ = controller.view
        controller.setSearchText("ReStArT Safari")
        let text = controller.searchField.attributedStringValue
        XCTAssertEqual(text.string, "ReStArT Safari")
        XCTAssertNotNil(text.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(text.attribute(.backgroundColor, at: 8, effectiveRange: nil))
        controller.setSearchText("Safari")
        XCTAssertNil(controller.searchField.attributedStringValue.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        controller.enterClipboardMode()
        controller.setSearchText("stop Safari")
        XCTAssertNil(controller.searchField.inlineCommand)
        controller.stopGlow()
    }

    func testFocusedEditorKeepsCaretAndUndoWhileStyling() throws {
        _ = NSApplication.shared
        PixelFont.registerBundledFonts()
        let controller = SearchViewController()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 764, height: 390),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.orderOut(nil); controller.stopGlow() }
        controller.setSearchText("restart Safari")
        controller.view.layoutSubtreeIfNeeded()
        controller.focus()
        let editor = try XCTUnwrap(controller.searchField.currentEditor() as? NSTextView)
        editor.allowsUndo = true
        editor.selectedRange = NSRange(location: 8, length: 6)
        controller.searchField.applyInlineStyle()
        XCTAssertEqual(editor.selectedRange, NSRange(location: 8, length: 6))
        XCTAssertNotNil(editor.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(editor.textStorage?.attribute(.backgroundColor, at: 8, effectiveRange: nil))
        editor.insertText("Code", replacementRange: editor.selectedRange)
        XCTAssertEqual(editor.string, "restart Code")
        XCTAssertNil(editor.textStorage?.attribute(.backgroundColor, at: 8, effectiveRange: nil))
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "restart Safari")
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.insertText(" x", replacementRange: editor.selectedRange)
        XCTAssertEqual(editor.string, "restart Safari x")
        XCTAssertNil(editor.typingAttributes[.backgroundColor])
        if let path = ProcessInfo.processInfo.environment["CSL_COMMAND_SNAPSHOT_DIR"] {
            for command in ProcessCommand.allCases {
                controller.setSearchText(command.rawValue)
                controller.apply(results: RunningApplicationProvider.results(programs: apps, command: command, query: ""), isSearching: false)
                controller.view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(command.rawValue + ".png"))
            }
        }
        controller.prepareForPresentation()
        XCTAssertNil(controller.searchField.inlineCommand)
    }

    func testRestartWaitsForExitAndLaunchesCapturedBundleOnce() async {
        var terminated = false, requests = 0, launches = 0
        let program = apps[0]
        let environment = ProcessActionRunner.Environment(resolve: { _ in
            .init(isTerminated: { terminated }, terminate: { requests += 1; return true })
        }, launch: { url in
            XCTAssertTrue(terminated)
            XCTAssertEqual(url, program.bundleURL)
            launches += 1
            return true
        })
        let task = Task { await ProcessActionRunner.run(.restart, program: program, environment: environment) }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(launches, 0)
        terminated = true
        let success = await task.value
        XCTAssertTrue(success)
        XCTAssertEqual(launches, 1)
    }

    func testRefusedQuitStaleTargetTimeoutAndCancelledActionNeverRelaunch() async {
        var launches = 0
        let missing = ProcessActionRunner.Environment(resolve: { _ in nil }, launch: { _ in launches += 1; return true })
        let refused = ProcessActionRunner.Environment(resolve: { _ in .init(isTerminated: { false }, terminate: { false }) }, launch: missing.launch)
        let timeout = ProcessActionRunner.Environment(resolve: { _ in .init(isTerminated: { false }, terminate: { true }) }, launch: missing.launch)
        for environment in [missing, refused, timeout] {
            let success = await ProcessActionRunner.run(.restart, program: apps[0], environment: environment, timeout: .zero)
            XCTAssertFalse(success)
        }
        let task = Task { await ProcessActionRunner.run(.restart, program: apps[0], environment: timeout) }
        await Task.yield()
        task.cancel()
        let cancelled = await task.value
        XCTAssertFalse(cancelled)
        XCTAssertEqual(launches, 0)
        let stopped = await ProcessActionRunner.run(.stop, program: apps[0], environment: .init(
            resolve: { _ in .init(isTerminated: { true }, terminate: { true }) }, launch: missing.launch))
        XCTAssertTrue(stopped)
        XCTAssertEqual(launches, 0)
    }
}
