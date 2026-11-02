import XCTest
import AppKit
@testable import CEPKit

@MainActor
final class ReturnKeyTests: XCTestCase {
    func testReturnForwardsRegardlessOfSearchWithoutInsertingAnEmoji() {
        _ = NSApplication.shared
        let picker = PickerViewController()
        _ = picker.view
        var inserts = 0
        var forwarded: [(UInt16, NSEvent.ModifierFlags)] = []
        picker.onInsert = { _, _ in inserts += 1; return true }
        picker.onReturnToTarget = { forwarded.append(($0, $1)) }
        for query in ["", "smile", "no-such-emoji-987654321"] {
            picker.setSearchText(query)
            for code: UInt16 in [36, 76] {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
                    timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code)!
                XCTAssertTrue(picker.handleReturnToTarget(event))
                XCTAssertEqual(forwarded.last?.0, code)
                XCTAssertEqual(forwarded.last?.1, .shift)
            }
        }
        XCTAssertEqual(forwarded.count, 6)
        XCTAssertEqual(inserts, 0)
        picker.prepareForHide()
    }

    func testHighlightedEmojiIsNotInsertedAgainAndRepeatedReturnIsConsumed() throws {
        _ = NSApplication.shared
        let picker = PickerViewController()
        _ = picker.view
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let grid = try XCTUnwrap(descendants(picker.view).compactMap { $0 as? EmojiGridView }.first)
        let emoji = EmojiItem(text: "😀", name: "grinning face", germanName: nil,
                              keywords: "smile", group: "Smileys", subgroup: "face", tones: nil,
                              kind: .emoji, sortIndex: 0)
        grid.setItems([emoji], resetSelection: true)
        XCTAssertEqual(grid.selectedItem, emoji)
        var inserts = 0, returns = 0
        picker.onInsert = { _, _ in inserts += 1; return true }
        picker.onReturnToTarget = { _, _ in returns += 1 }
        for repeated in [false, true] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: repeated, keyCode: 36)!
            XCTAssertTrue(picker.handleReturnToTarget(event))
        }
        XCTAssertEqual(returns, 1)
        XCTAssertEqual(inserts, 0)
        picker.prepareForHide()
    }

    func testForwardedEventsArePhysicalReturnWithOriginalModifiers() {
        for code: UInt16 in [36, 76] {
            for flags: NSEvent.ModifierFlags in [[], .shift, [.command, .shift]] {
                let events = TextInjector.returnEvents(keyCode: code, flags: flags)
                XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
                XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [Int64(code), Int64(code)])
                XCTAssertEqual(events.map { $0.flags.rawValue }, [UInt64(flags.rawValue), UInt64(flags.rawValue)])
            }
        }
        XCTAssertTrue(TextInjector.returnEvents(keyCode: 0, flags: []).isEmpty)
    }
}
