import XCTest
import AppKit
@testable import CSL

@MainActor
final class ResultDraggingTests: XCTestCase {
    private func result(_ name: String, action: ResultAction? = nil) -> SearchResult {
        let url = URL(fileURLWithPath: "/tmp/CSL Drag Tests/\(name)")
        return SearchResult(id: name, title: name, subtitle: url.path, kind: .file,
                            icon: .glyph(.globe), score: 1, titleMatch: [], action: action ?? .open(url))
    }

    private func controller() -> SearchViewController {
        _ = NSApplication.shared
        let controller = SearchViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 764, height: 518)
        controller.setSearchText("clip")
        controller.apply(results: [result("clip ü #1.mov")], isSearching: false)
        return controller
    }

    func testFilePasteboardRoundTripsModernAndLegacyReadersWithoutPromises() throws {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: "/tmp/CSL Drag Tests/clip ü #1.mov")
        for action in [ResultAction.open(url), .reveal(url)] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            XCTAssertTrue(board.writeObjects([ResultDragging.writer(for: result("clip", action: action))]))
            let urls = try XCTUnwrap(board.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL])
            XCTAssertEqual(urls, [url])
            XCTAssertEqual(board.propertyList(forType: ResultDragging.filenamesType) as? [String], [url.path])
            XCTAssertFalse((board.types ?? []).contains { $0.rawValue.lowercased().contains("promise") })
        }
    }

    func testWebsiteAndCommandKeepTheirOwnPayloadTypes() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = URL(string: "https://example.com/media?q=clip")!
        XCTAssertTrue(board.writeObjects([ResultDragging.writer(for: result("website", action: .open(url)))]))
        XCTAssertEqual(board.string(forType: .URL), url.absoluteString)
        XCTAssertNil(board.propertyList(forType: ResultDragging.filenamesType))
        board.clearContents()
        var ran = false
        XCTAssertTrue(board.writeObjects([ResultDragging.writer(for: result("command", action: .run { ran = true }))]))
        XCTAssertEqual(board.string(forType: .string), "command")
        XCTAssertFalse(ran)
    }

    func testDragStartsInEveryDirectionButIgnoresClickJitter() {
        let origin = NSPoint(x: 100, y: 100)
        XCTAssertFalse(ResultDragging.shouldBegin(from: origin, to: NSPoint(x: 102, y: 102)))
        for delta in [NSPoint(x: 4, y: 0), NSPoint(x: -4, y: 0),
                      NSPoint(x: 0, y: 4), NSPoint(x: 0, y: -4)] {
            XCTAssertTrue(ResultDragging.shouldBegin(from: origin,
                to: NSPoint(x: origin.x + delta.x, y: origin.y + delta.y)))
        }
    }

    func testCompactPreviewKeepsPointerOffsetAcrossTheRow() {
        _ = NSApplication.shared
        let first = ResultDragging.item(for: result("clip.mov"), at: NSPoint(x: 20, y: 10))
        let last = ResultDragging.item(for: result("clip.mov"), at: NSPoint(x: 700, y: 10))
        XCTAssertEqual(first.draggingFrame.size, NSSize(width: 260, height: 36))
        XCTAssertEqual(last.draggingFrame.minX - first.draggingFrame.minX, 680)
        XCTAssertEqual(first.draggingFrame.minY, last.draggingFrame.minY)
    }

    func testCancelledDragFreezesResultsThenAppliesLatestBatchWithoutOpening() {
        let controller = controller()
        defer { controller.stopGlow() }
        let table = NSTableView()
        var opened = false
        var dismissed = false
        controller.onChoose = { _, _ in opened = true }
        controller.onDragDismiss = { dismissed = true }
        controller.apply(results: [result("clip ü #1.mov")], isSearching: true)
        XCTAssertTrue(controller.control(controller.searchField, textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        let height = controller.preferredContentHeight
        controller.beginResultDrag(at: 0)
        controller.apply(results: [result("replacement.mov"), result("second.mov")], isSearching: true)
        controller.apply(results: [result("final.mov")], isSearching: false)
        XCTAssertEqual(controller.numberOfRows(in: table), 1)
        XCTAssertEqual(controller.preferredContentHeight, height)
        XCTAssertTrue(controller.isDraggingResult)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects([controller.tableView(table, pasteboardWriterForRow: 0)!]))
        XCTAssertTrue(board.string(forType: .fileURL)!.contains("clip"))
        controller.endResultDrag(operation: [])
        board.clearContents()
        XCTAssertTrue(board.writeObjects([controller.tableView(table, pasteboardWriterForRow: 0)!]))
        XCTAssertTrue(board.string(forType: .fileURL)!.contains("final.mov"))
        XCTAssertFalse(controller.isDraggingResult)
        XCTAssertFalse(opened)
        XCTAssertFalse(dismissed)
    }

    func testSuccessfulDropRecordsOriginalResultAndDismissesImmediately() {
        let controller = controller()
        defer { controller.stopGlow() }
        var recorded: String?
        var dismissed = false
        controller.onDragOut = { recorded = $0.id }
        controller.onDragDismiss = { dismissed = true }
        controller.beginResultDrag(at: 0)
        controller.apply(results: [result("replacement.mov")], isSearching: false)
        controller.endResultDrag(operation: .copy)
        XCTAssertEqual(recorded, "clip ü #1.mov")
        XCTAssertTrue(dismissed)
        XCTAssertFalse(controller.isDraggingResult)
    }

    func testStaleResultCannotBeginDrag() {
        let controller = controller()
        defer { controller.stopGlow() }
        controller.setSearchText("different")
        controller.beginResultDrag(at: 0)
        XCTAssertFalse(controller.isDraggingResult)
        XCTAssertNil(controller.tableView(NSTableView(), pasteboardWriterForRow: 0))
    }

    func testClickSelectsAndDoubleClickOpensAfterCancelledDrag() throws {
        let controller = controller()
        defer { controller.stopGlow() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 764, height: 518),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? ResultScrollView }.first)
        let table = try XCTUnwrap(scroll.documentView as? ResultTableView)
        var opened: [String] = []
        controller.onChoose = { result, _ in opened.append(result.id) }
        controller.beginResultDrag(at: 0)
        controller.endResultDrag(operation: [])

        let point = table.convert(NSPoint(x: 60, y: table.rect(ofRow: 0).midY), to: nil)
        for count in [1, 2] {
            let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: count, pressure: 1))
            let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
                modifierFlags: [], timestamp: 0.01, windowNumber: window.windowNumber,
                context: nil, eventNumber: 2, clickCount: count, pressure: 0))
            NSApp.postEvent(up, atStart: true)
            table.mouseDown(with: down)
            XCTAssertFalse(table.isTrackingMouse)
            XCTAssertEqual(opened.count, count == 1 ? 0 : 1)
        }
        XCTAssertEqual(opened, ["clip ü #1.mov"])
    }
}
