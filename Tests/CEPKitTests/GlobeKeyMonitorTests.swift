import XCTest
import CoreGraphics
@testable import CEPKit

final class GlobeKeyMonitorTests: XCTestCase {
    func testStandaloneFnTapStillOpensPicker() {
        let monitor = GlobeKeyMonitor()
        var releases: [Bool] = []
        monitor.onFnUp = { releases.append($0) }
        monitor.observeEvent(type: .flagsChanged, keyCode: 63, flags: .maskSecondaryFn,
                             hardwareFnAvailable: false, at: 1)
        monitor.observeEvent(type: .flagsChanged, keyCode: 63, flags: [],
                             hardwareFnAvailable: false, at: 1.1)
        XCTAssertEqual(releases, [false])
    }

    func testAllFunctionKeysAndArrowsPreventPickerWithHardwareFn() {
        for code: Int64 in [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 123, 124, 125, 126] {
            let monitor = GlobeKeyMonitor()
            var releases: [Bool] = []
            monitor.onFnUp = { releases.append($0) }
            monitor.fnPressed(at: 1)
            // Some transformed events no longer carry the physical Fn flag.
            monitor.observeEvent(type: .keyDown, keyCode: code, flags: [], hardwareFnAvailable: true, at: 1.1)
            XCTAssertTrue(monitor.fnIsDown)
            monitor.fnReleased(at: 1.2)
            XCTAssertEqual(releases, [true], "key code \(code)")
        }
    }

    func testConsumerAndKeyboardReportsPreventPicker() {
        for (page, usage): (UInt32, UInt32) in [(7, 0x3A), (7, 0xE1), (0x0C, 0xE9)] {
            let monitor = GlobeKeyMonitor()
            var releases: [Bool] = []
            monitor.onFnUp = { releases.append($0) }
            monitor.fnPressed(at: 1)
            monitor.observeHIDValue(page: page, usage: usage, value: 1)
            monitor.fnReleased(at: 1.1)
            XCTAssertEqual(releases, [true])
        }
    }

    func testFunctionFlagOnRegularKeyNeverCreatesFnTap() {
        let monitor = GlobeKeyMonitor()
        var downs = 0
        monitor.onFnDown = { downs += 1 }
        monitor.observeEvent(type: .keyDown, keyCode: 122, flags: .maskSecondaryFn, hardwareFnAvailable: false, at: 1)
        monitor.observeEvent(type: .keyUp, keyCode: 122, flags: [], hardwareFnAvailable: false, at: 1.1)
        XCTAssertEqual(downs, 0)
    }

    func testFallbackChordAndShiftFnDoNotOpenPicker() {
        for flags: CGEventFlags in [.maskSecondaryFn, [.maskSecondaryFn, .maskShift]] {
            let monitor = GlobeKeyMonitor()
            var releases: [Bool] = []
            monitor.onFnUp = { releases.append($0) }
            monitor.observeEvent(type: .flagsChanged, keyCode: 63, flags: flags, hardwareFnAvailable: false, at: 1)
            monitor.observeEvent(type: .keyDown, keyCode: 120, flags: flags, hardwareFnAvailable: false, at: 1.05)
            monitor.observeEvent(type: .flagsChanged, keyCode: 63, flags: [], hardwareFnAvailable: false, at: 1.1)
            XCTAssertEqual(releases, [true])
        }
    }
}
