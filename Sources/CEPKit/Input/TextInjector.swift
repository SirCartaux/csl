import AppKit
import ApplicationServices
import CoreGraphics

/// Types a string straight into the target process.
///
/// `CGEvent.postToPid` bypasses the active application: the picker can stay
/// key and focused while the emoji lands in the text field that was focused
/// before the picker opened. No pasteboard round-trip, no app activation and
/// therefore no visible delay.
enum TextInjector {
    static func insert(_ text: String, into pid: pid_t) -> Bool {
        guard pid > 0, !text.isEmpty else { return false }
        guard AXIsProcessTrusted() else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }

        let units = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        down.flags = []
        up.flags = []

        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
