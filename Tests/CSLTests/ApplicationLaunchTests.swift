import XCTest
import AppKit
@testable import CSL

@MainActor
final class ApplicationLaunchTests: XCTestCase {
    private func result(_ id: String) -> SearchResult {
        SearchResult(id: id, title: id, subtitle: "Application", kind: .application,
                     icon: .glyph(.globe), score: 1, titleMatch: [],
                     action: .open(URL(fileURLWithPath: "/Applications/\(id).app")))
    }

    func testLaunchImmediatelyLeavesOnlyClickedRowAndRejectsLateSearchBatches() throws {
        _ = NSApplication.shared
        let controller = SearchViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 764, height: 518)
        controller.apply(results: [result("first"), result("chosen"), result("last")], isSearching: false)
        controller.view.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(controller.view as? RootView)
        let before = root.subviews.map { ($0, $0.isHidden) }
        let scroll = try XCTUnwrap(root.subviews.compactMap { $0 as? NSScrollView }.first)
        let table = try XCTUnwrap(scroll.documentView as? NSTableView)
        let expectedFrame = root.convert(table.rect(ofRow: 1), from: table)
        let height = controller.preferredContentHeight

        controller.markLaunching(result("chosen"), isolate: true)
        XCTAssertTrue(root.showsOnlyLaunchingResult)
        XCTAssertTrue(controller.searchField.isHidden)
        let visible = root.subviews.filter { !$0.isHidden }
        XCTAssertEqual(visible.count, 1)
        let row = try XCTUnwrap(visible.first as? ResultRowView)
        XCTAssertEqual(row.frame, expectedFrame)
        controller.apply(results: [result("late")], isSearching: false)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(row.frame, expectedFrame)
        XCTAssertEqual(controller.preferredContentHeight, height)
        XCTAssertEqual(controller.numberOfRows(in: table), 3)

        controller.finishLaunching(success: true)
        controller.apply(results: [result("late during fade")], isSearching: false)
        XCTAssertEqual(controller.numberOfRows(in: table), 3)
        XCTAssertTrue(root.showsOnlyLaunchingResult, "Do not flash the full list before dismissing")
        controller.restoreLaunchPresentation()
        XCTAssertFalse(root.showsOnlyLaunchingResult)
        for (view, hidden) in before { XCTAssertEqual(view.isHidden, hidden) }
        controller.stopGlow()
    }

    func testFailedLaunchRestoresSearchAndNextPresentationResetsIsolation() throws {
        _ = NSApplication.shared
        let controller = SearchViewController()
        controller.view.frame = CGRect(x: 0, y: 0, width: 764, height: 518)
        controller.setSearchText("chosen")
        controller.apply(results: [result("chosen")], isSearching: false)
        controller.markLaunching(result("chosen"), isolate: true)
        controller.finishLaunching(success: false)
        let root = try XCTUnwrap(controller.view as? RootView)
        XCTAssertFalse(root.showsOnlyLaunchingResult)
        XCTAssertFalse(controller.searchField.isHidden)
        XCTAssertTrue(controller.searchField.isEditable)
        XCTAssertEqual(controller.searchField.stringValue, "chosen")
        controller.markLaunching(result("chosen"), isolate: true)
        controller.restoreLaunchPresentation() // Hotkey interrupts the closing animation.
        XCTAssertTrue(controller.searchField.isEditable)
        controller.apply(results: [result("new")], isSearching: false)
        XCTAssertEqual(controller.numberOfRows(in: NSTableView()), 1)
        controller.markLaunching(result("new"), isolate: true)
        controller.prepareForPresentation()
        XCTAssertFalse(root.showsOnlyLaunchingResult)
        XCTAssertFalse(controller.searchField.isHidden)
        controller.stopGlow()
    }

    func testReadinessWaitsForWindowAfterProcessStartupAndCompletesOnce() async throws {
        let waiter = ApplicationWindowWaiter()
        defer { waiter.cancel() }
        var finished = false, visible = false
        var completions: [Bool] = []
        var probes = 0
        waiter.wait(state: { .init(processID: 42, finishedLaunching: finished, terminated: false) },
                    hasWindow: { pid in XCTAssertEqual(pid, 42); probes += 1; return visible },
                    interval: .milliseconds(5), completion: { completions.append($0) })
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(probes, 0)
        finished = true
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertGreaterThan(probes, 0)
        XCTAssertTrue(completions.isEmpty, "Launch completion alone must not dismiss the row")
        visible = true
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(completions, [true])
    }

    func testCancelDropsInFlightProbeAndTerminationReportsFailure() async throws {
        let waiter = ApplicationWindowWaiter()
        defer { waiter.cancel() }
        var completions: [Bool] = []
        var continuation: CheckedContinuation<Bool, Never>?
        waiter.wait(state: { .init(processID: 42, finishedLaunching: true, terminated: false) },
                    hasWindow: { _ in await withCheckedContinuation { continuation = $0 } },
                    completion: { completions.append($0) })
        while continuation == nil { await Task.yield() }
        waiter.cancel()
        waiter.wait(state: { .init(processID: 43, finishedLaunching: false, terminated: true) },
                    hasWindow: { _ in XCTFail("A terminated app cannot have a ready window"); return true },
                    completion: { completions.append($0) })
        continuation?.resume(returning: true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(completions, [false], "A cancelled probe must not finish a newer launch")
    }

    func testWindowProbeRejectsOtherAppsHiddenWindowsAndNonWindowLayers() {
        let window: [String: Any] = [
            kCGWindowOwnerPID as String: 42, kCGWindowLayer as String: 0,
            kCGWindowIsOnscreen as String: true, kCGWindowAlpha as String: 1,
            kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 800, height: 600).dictionaryRepresentation
        ]
        XCTAssertTrue(ApplicationWindowProbe.isVisibleApplicationWindow(window, processID: 42))
        XCTAssertFalse(ApplicationWindowProbe.isVisibleApplicationWindow(window, processID: 43))
        for (key, value): (String, Any) in [
            (kCGWindowIsOnscreen as String, false), (kCGWindowAlpha as String, 0),
            (kCGWindowLayer as String, 25),
            (kCGWindowBounds as String, CGRect.zero.dictionaryRepresentation)
        ] {
            var candidate = window
            candidate[key] = value
            XCTAssertFalse(ApplicationWindowProbe.isVisibleApplicationWindow(candidate, processID: 42))
        }
    }
}
