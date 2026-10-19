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
        _ = controller.control(controller.searchField, textView: NSTextView(),
                               doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(chosen, ["document"])
        controller.apply(results: [result("document")], isSearching: false)
        XCTAssertLessThan(controller.preferredContentHeight, height)
        controller.stopGlow()
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
