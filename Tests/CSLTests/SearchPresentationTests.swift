import XCTest
import AppKit
@testable import CSL

@MainActor
final class SearchPresentationTests: XCTestCase {
    private func result(_ id: String) -> SearchResult {
        SearchResult(id: id, title: id, subtitle: "", kind: .command,
                     icon: .glyph(.globe), score: 1, titleMatch: [], action: .run({}))
    }

    func testRapidQueriesKeepRowsAndHeightUntilReplacementWithoutOpeningStaleResults() {
        _ = NSApplication.shared
        let controller = SearchViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 764, height: 518)
        let table = NSTableView()
        var chosen: [String] = []
        controller.onChoose = { result, _ in chosen.append(result.id) }
        controller.setSearchText("doc")
        controller.apply(results: (0..<7).map { result("doc\($0)") }, isSearching: false)
        let height = controller.preferredContentHeight
        for query in ["docu", "docum", "docume", "document"] {
            controller.setSearchText(query)
            controller.apply(results: [], isSearching: true)
            XCTAssertEqual(controller.numberOfRows(in: table), 7)
            XCTAssertEqual(controller.preferredContentHeight, height)
            XCTAssertTrue(controller.control(controller.searchField, textView: NSTextView(),
                                              doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertTrue(chosen.isEmpty)
            XCTAssertTrue(controller.debugContextMenuTitles(for: 0).isEmpty)
            XCTAssertNil(controller.tableView(table, pasteboardWriterForRow: 0))
        }
        controller.apply(results: [result("document")], isSearching: true)
        XCTAssertEqual(controller.numberOfRows(in: table), 1)
        XCTAssertEqual(controller.preferredContentHeight, height)
        XCTAssertEqual(chosen, ["document"])

        // The first partial batch consumes Enter; final ranking cannot reopen it.
        controller.apply(results: [result("document")], isSearching: false)
        XCTAssertEqual(chosen, ["document"])
        XCTAssertLessThan(controller.preferredContentHeight, height)
        controller.stopGlow()
    }

    func testEnterOpensSelectedPartialResultSynchronously() {
        _ = NSApplication.shared
        let controller = SearchViewController()
        _ = controller.view
        controller.setSearchText("doc")
        controller.apply(results: [result("doc1"), result("doc2")], isSearching: true)
        _ = controller.control(controller.searchField, textView: NSTextView(),
                               doCommandBy: #selector(NSResponder.moveDown(_:)))
        var chosen: [(String, Bool)] = []
        controller.onChoose = { chosen.append(($0.id, $1)) }
        controller.openSelectionWhenAvailable(reveal: true)
        XCTAssertEqual(chosen.map(\.0), ["doc2"])
        XCTAssertEqual(chosen.map(\.1), [true])
        controller.apply(results: [result("doc3")], isSearching: false)
        XCTAssertEqual(chosen.count, 1)
        controller.stopGlow()
    }

    func testQueuedEnterIsCancelledByEditingAndUsesFirstBatchOnly() {
        _ = NSApplication.shared
        let controller = SearchViewController()
        _ = controller.view
        var chosen: [String] = []
        controller.onChoose = { result, _ in chosen.append(result.id) }
        controller.setSearchText("missing")
        controller.openSelectionWhenAvailable(reveal: false)
        controller.setSearchText("new")
        controller.apply(results: [result("new1")], isSearching: true)
        XCTAssertTrue(chosen.isEmpty)
        controller.setSearchText("later")
        controller.openSelectionWhenAvailable(reveal: false)
        controller.apply(results: [], isSearching: true)
        XCTAssertTrue(chosen.isEmpty)
        controller.apply(results: [result("later1")], isSearching: true)
        XCTAssertEqual(chosen, ["later1"])
        controller.apply(results: [result("later2")], isSearching: false)
        XCTAssertEqual(chosen, ["later1"])
        controller.stopGlow()
    }

    func testEnterFlushesTypingDebounceAndCancellationStopsRemainingProviders() {
        final class Delegate: SearchEngineDelegate {
            let controller: SearchViewController
            var batches = 0
            init(_ controller: SearchViewController) { self.controller = controller }
            func searchEngine(_ engine: SearchEngine, didUpdate results: [SearchResult], isSearching: Bool) {
                batches += 1
                controller.apply(results: results, isSearching: isSearching)
            }
        }
        _ = NSApplication.shared
        let controller = SearchViewController(), engine = SearchEngine()
        controller.engine = engine
        _ = controller.view
        let delegate = Delegate(controller)
        engine.delegate = delegate
        var chosen: [String] = []
        var lateProgress = 0
        engine.onIndexProgress = { _, _, _ in if !chosen.isEmpty { lateProgress += 1 } }
        controller.onChoose = { result, _ in
            engine.cancel()
            chosen.append(result.id)
        }
        controller.setSearchText("clipboard")
        XCTAssertEqual(delegate.batches, 0)
        controller.openSelectionWhenAvailable(reveal: false)
        XCTAssertEqual(chosen, ["cmd:clipboard"])
        XCTAssertEqual(delegate.batches, 1)
        XCTAssertEqual(lateProgress, 0)
        controller.stopGlow()
        engine.cancel()
    }

    func testFinalMissClearsRetainedRowsAndQueryResetIsImmediate() {
        _ = NSApplication.shared
        let controller = SearchViewController()
        _ = controller.view
        let table = NSTableView()
        controller.setSearchText("known")
        controller.apply(results: [result("known")], isSearching: false)
        controller.setSearchText("missing")
        controller.apply(results: [], isSearching: true)
        XCTAssertEqual(controller.numberOfRows(in: table), 1)
        controller.apply(results: [], isSearching: false)
        XCTAssertEqual(controller.numberOfRows(in: table), 0)
        XCTAssertFalse((controller.view as! RootView).isSearching)
        controller.setSearchText("")
        controller.apply(results: [result("default")], isSearching: false)
        XCTAssertEqual(controller.numberOfRows(in: table), 1)
        XCTAssertFalse(controller.debugContextMenuTitles(for: 0).isEmpty)
        controller.stopGlow()
    }
}
