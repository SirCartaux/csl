import XCTest
import AppKit
@testable import CSL

@MainActor
final class SearchSuggestionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        PixelFont.registerBundledFonts()
    }

    private func snapshot(_ controller: SearchViewController, name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["CSL_COMMAND_SNAPSHOT_DIR"] else { return }
        controller.view.layoutSubtreeIfNeeded()
        controller.view.window?.displayIfNeeded()
        controller.view.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        let bitmap = try XCTUnwrap(controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
    }

    private func history() -> (QuerySuggestionHistory, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (QuerySuggestionHistory(file: folder.appendingPathComponent("suggestions.json"), center: NotificationCenter()), folder)
    }

    private func result(_ title: String) -> SearchResult {
        SearchResult(id: title, title: title, subtitle: "APPLICATION", kind: .application, icon: .glyph(.gear),
                     score: 900, titleMatch: [], action: .open(URL(fileURLWithPath: "/Applications/\(title).app")))
    }

    private func press(_ selector: Selector, in controller: SearchViewController) {
        _ = controller.control(controller.searchField, textView: NSTextView(), doCommandBy: selector)
    }

    private final class Delegate: SearchEngineDelegate {
        var results: [SearchResult] = []
        var controller: SearchViewController?
        func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool) {
            self.results = results
            MainActor.assumeIsolated { controller?.apply(results: results, isSearching: isSearching) }
        }
    }

    func testPrefixSuggestionsFillWithoutActivatingOrExecutingCommands() throws {
        let stops = SearchSuggestions.prefixes(for: "sTo", shortcuts: [])
        let suggestion = try XCTUnwrap(stops.first)
        guard case .complete(let completion) = suggestion.action else { return XCTFail("Expected input completion") }
        XCTAssertEqual(completion, "stop ")
        XCTAssertTrue(SearchSuggestions.prefixes(for: "some unrelated text", shortcuts: []).isEmpty)
        let custom = SearchShortcut(id: UUID(), prefix: "KL", name: "Kleinanzeigen",
            searchTemplate: "https://www.kleinanzeigen.de/s-{query}/k0", siteURL: "https://www.kleinanzeigen.de",
            tintHex: "#9BD450", iconFileName: nil)
        for input in ["k", "kl", "klein"] {
            XCTAssertEqual(SearchSuggestions.prefixes(for: input, shortcuts: [custom]).first?.inputCompletion, "KL ")
        }
        let (store, folder) = history()
        defer { try? FileManager.default.removeItem(at: folder) }
        var snapshots = 0
        let provider = RunningApplicationProvider(snapshot: { snapshots += 1; return [] }, center: NotificationCenter())
        let engine = SearchEngine(processProvider: provider, suggestionHistory: store)
        let controller = SearchViewController(), delegate = Delegate()
        controller.engine = engine
        delegate.controller = controller
        engine.delegate = delegate
        _ = controller.view
        var executed = 0
        controller.onChoose = { _, _ in executed += 1 }
        controller.setSearchText("sto")
        press(#selector(NSResponder.insertTab(_:)), in: controller) // Flush the typing debounce.
        XCTAssertTrue(delegate.results.contains { $0.id == "complete:stop" })
        XCTAssertEqual(snapshots, 0)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        XCTAssertEqual(controller.searchField.stringValue, "stop ")
        XCTAssertEqual(snapshots, 1)
        XCTAssertEqual(executed, 0, "Accepting a prefix must never quit a program")
        engine.cancel()
        controller.stopGlow()
    }

    func testHistoryIsBoundedDeduplicatedScopedAndPersistsClear() throws {
        let (store, folder) = history()
        defer { try? FileManager.default.removeItem(at: folder) }
        store.record(scope: "google", query: "Camera lenses")
        store.record(scope: "google", query: "camera lenses")
        store.record(scope: "other", query: "Camera bags")
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.matching(scope: "google", query: "cam"), ["camera lenses"])
        XCTAssertTrue(store.matching(scope: "google", query: "camera lenses").isEmpty)
        for i in 0..<120 { store.record(scope: "google", query: "query \(i)") }
        XCTAssertEqual(store.entries.count, QuerySuggestionHistory.limit)
        store.waitForWrites()
        let reloaded = QuerySuggestionHistory(file: folder.appendingPathComponent("suggestions.json"), center: NotificationCenter())
        XCTAssertEqual(reloaded.entries.count, QuerySuggestionHistory.limit)
        XCTAssertEqual(reloaded.entries.first?.query, "query 119")
        store.clear()
        store.waitForWrites()
        XCTAssertTrue(QuerySuggestionHistory(file: folder.appendingPathComponent("suggestions.json")).entries.isEmpty)
    }

    func testHistorySuggestionsKeepTypedSearchFirstAndEncodeSelectedQuery() throws {
        let (store, folder) = history()
        defer { store.waitForWrites(); try? FileManager.default.removeItem(at: folder) }
        let raw = "google C"
        let command = try XCTUnwrap(InlineCommand.parse(raw, shortcuts: []))
        store.record(scope: "google", query: "C++ & Größe + 2")
        store.record(scope: "other", query: "Cross-provider secret")
        let direct = try XCTUnwrap(WebSearchProvider.result(for: raw))
        let results = SearchSuggestions.webResults(command: command, raw: raw, direct: direct, history: store)
        XCTAssertEqual(results.first?.id, direct.id)
        XCTAssertEqual(results.count, 2)
        let suggestion = results[1]
        XCTAssertEqual(suggestion.title, "C++ & Größe + 2")
        XCTAssertEqual(suggestion.inputCompletion, "google C++ & Größe + 2")
        guard case .open(let url) = suggestion.action else { return XCTFail("Expected search URL") }
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "q", value: "C++ & Größe + 2")])
        store.recordSuccessful(suggestion, raw: raw)
        XCTAssertEqual(store.entries.first?.query, "C++ & Größe + 2", "Store the accepted suggestion, not its typed prefix")
        XCTAssertFalse(store.entries.contains { $0.query == "C" })
    }

    func testWebPrefixShowsRecentSearchesWithoutStartingProcessProvider() throws {
        let (store, folder) = history()
        defer { store.waitForWrites(); try? FileManager.default.removeItem(at: folder) }
        store.record(scope: "google", query: "camera lenses")
        var snapshots = 0
        let provider = RunningApplicationProvider(snapshot: { snapshots += 1; return [] }, center: NotificationCenter())
        let engine = SearchEngine(processProvider: provider, suggestionHistory: store), delegate = Delegate()
        engine.delegate = delegate
        engine.search("google ")
        XCTAssertEqual(delegate.results.map(\.title), ["camera lenses"])
        engine.search("google cam")
        XCTAssertEqual(delegate.results.count, 2)
        XCTAssertEqual(snapshots, 0)
        engine.cancel()
    }

    func testFirstTabSelectsFirstThenCyclesAndEnterUsesSelectedResult() {
        let controller = SearchViewController()
        _ = controller.view
        controller.apply(results: [result("Safari"), result("Mail"), result("Code")], isSearching: false)
        var chosen: [String] = []
        controller.onChoose = { result, _ in chosen.append(result.title) }
        press(#selector(NSResponder.insertTab(_:)), in: controller)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        press(#selector(NSResponder.insertTab(_:)), in: controller)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        press(#selector(NSResponder.insertBacktab(_:)), in: controller)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        press(#selector(NSResponder.insertBacktab(_:)), in: controller)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        XCTAssertEqual(chosen, ["Safari", "Mail", "Safari", "Code"])
        XCTAssertEqual(controller.searchField.stringValue, "", "Browsing results must leave the input editable and unchanged")
        controller.stopGlow()
    }

    func testTabWaitsForFreshResultsAndNeverActsOnOldRows() {
        let controller = SearchViewController()
        _ = controller.view
        controller.apply(results: [result("Old")], isSearching: false)
        controller.setSearchText("new")
        var chosen: [String] = []
        controller.onChoose = { result, _ in chosen.append(result.title) }
        press(#selector(NSResponder.insertTab(_:)), in: controller)
        press(#selector(NSResponder.insertTab(_:)), in: controller)
        XCTAssertTrue(chosen.isEmpty)
        press(#selector(NSResponder.insertNewline(_:)), in: controller)
        XCTAssertTrue(chosen.isEmpty)
        controller.apply(results: [], isSearching: true)
        controller.apply(results: [result("New first"), result("New second")], isSearching: false)
        XCTAssertEqual(chosen, ["New second"])
        controller.stopGlow()
    }

    func testGhostCompletionAndRightArrowNeverExecuteAndPreserveCaretEditing() throws {
        PixelFont.registerBundledFonts()
        let controller = SearchViewController()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 764, height: 390),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer { window.orderOut(nil); controller.stopGlow() }
        controller.setSearchText("Saf")
        controller.stopGlow() // Cancel the file-search debounce; inject a controlled provider result.
        controller.focus()
        controller.view.layoutSubtreeIfNeeded()
        controller.apply(results: [result("Safari")], isSearching: false)
        XCTAssertEqual(controller.searchField.stringValue, "Saf")
        XCTAssertEqual(controller.completionView.suffix, "ari")
        XCTAssertFalse(controller.completionView.isHidden)
        try snapshot(controller, name: "completion-smooth")
        var executions = 0
        controller.onChoose = { _, _ in executions += 1 }
        let editor = try XCTUnwrap(controller.searchField.currentEditor() as? NSTextView)
        editor.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertFalse(controller.completeSelectedInput(), "Right arrow inside the query must keep native cursor movement")
        editor.selectedRange = NSRange(location: 3, length: 0)
        XCTAssertTrue(controller.completeSelectedInput())
        XCTAssertEqual(controller.searchField.stringValue, "Safari")
        XCTAssertEqual(executions, 0)
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "Saf", "An accepted completion must undo back to the typed query")
        XCTAssertEqual(SearchCompletionView.suffix(for: "sAf", completion: "Safari"), "ari")
        XCTAssertNil(SearchCompletionView.suffix(for: "vsco", completion: "Visual Studio Code"))
        controller.setSearchText("sto")
        controller.stopGlow()
        controller.focus()
        controller.apply(results: SearchSuggestions.prefixes(for: "sto", shortcuts: []), isSearching: false)
        try snapshot(controller, name: "prefix-suggestions-smooth")
    }
}
