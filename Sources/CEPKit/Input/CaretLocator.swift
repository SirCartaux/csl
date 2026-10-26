import AppKit
import ApplicationServices

/// The text cursor we should attach the picker to. `axRect` is in the global
/// Quartz display coordinate space (origin top-left, y grows down).
struct CaretAnchor {
    var axRect: CGRect
    var pid: pid_t
    var appName: String?
    var hadAccessibility: Bool
}

enum CaretLocator {
    static var isTrusted: Bool { AXIsProcessTrusted() }
    private static var manualAccessibilityEnabled = Set<pid_t>()

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Reads the currently focused AX element. Call this *before* the picker
    /// becomes key, otherwise the focused element may be our own search field.
    static func capture(preferredPID: pid_t? = nil) -> CaretAnchor? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        var element: AXUIElement?

        if AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            let candidate = focusedRef as! AXUIElement
            var pid: pid_t = 0
            AXUIElementGetPid(candidate, &pid)
            if pid != ProcessInfo.processInfo.processIdentifier {
                element = candidate
            }
        }

        var applicationElement: AXUIElement?
        if let preferredPID, preferredPID > 0 {
            let application = AXUIElementCreateApplication(preferredPID)
            applicationElement = application
            // Chromium/Electron apps only build their AX tree after this
            // switch is set. It is harmless (and returns an error) on native
            // apps, and it makes web text fields positionable.
            if manualAccessibilityEnabled.insert(preferredPID).inserted {
                AXUIElementSetAttributeValue(
                    application,
                    "AXManualAccessibility" as CFString,
                    kCFBooleanTrue
                )
            }
        }

        if element == nil, let application = applicationElement {
            var candidateRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &candidateRef
            ) == .success, let candidateRef, CFGetTypeID(candidateRef) == AXUIElementGetTypeID() {
                let candidate = candidateRef as! AXUIElement
                var pid: pid_t = 0
                AXUIElementGetPid(candidate, &pid)
                if pid != ProcessInfo.processInfo.processIdentifier {
                    element = candidate
                }
            }
        }

        // Web views and some Electron apps do not publish the system-wide
        // focused element. Walk the app's focused window for a focused text
        // control instead; the budget keeps this off the critical path.
        if element == nil, let application = applicationElement {
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                application,
                kAXFocusedWindowAttribute as CFString,
                &windowRef
            ) == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                var budget = 320
                let start = CFAbsoluteTimeGetCurrent()
                element = findFocusedTextElement(
                    in: windowRef as! AXUIElement,
                    depth: 0,
                    budget: &budget,
                    deadline: start + 0.08
                )
            }
        }

        guard let element else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let appName = pid > 0
            ? NSRunningApplication(processIdentifier: pid)?.localizedName
            : nil

        let rect = caretRect(for: element)
        return CaretAnchor(
            axRect: rect,
            pid: pid,
            appName: appName,
            hadAccessibility: isTrusted
        )
    }

    /// Last-resort anchor when AX does not expose a caret (games, some web
    /// views): the pointer position. In AppKit screen coordinates.
    static func mouseAnchor() -> CGRect {
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y, width: 2, height: 18)
    }

    private static func findFocusedTextElement(
        in element: AXUIElement,
        depth: Int,
        budget: inout Int,
        deadline: CFAbsoluteTime
    ) -> AXUIElement? {
        guard depth < 14, budget > 0, CFAbsoluteTimeGetCurrent() < deadline else { return nil }
        budget -= 1

        var role = ""
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success {
            role = roleRef as? String ?? ""
        }
        let textRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            kAXComboBoxRole as String
        ]
        if textRoles.contains(role) {
            var focusedRef: CFTypeRef?
            let focused = AXUIElementCopyAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                &focusedRef
            ) == .success && (focusedRef as? Bool == true)
            if focused {
                return element
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findFocusedTextElement(
                in: child,
                depth: depth + 1,
                budget: &budget,
                deadline: deadline
            ) {
                return found
            }
        }
        return nil
    }

    private static func caretRect(for element: AXUIElement) -> CGRect {
        // Try the selected text range first: this is the actual insertion point.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                for length in [max(1, range.length), 0] {
                    var probe = CFRange(location: range.location, length: length)
                    if let rangeValue = AXValueCreate(.cfRange, &probe),
                       let rect = bounds(for: element, range: rangeValue) {
                        return rect
                    }
                }
            }
        }

        // Fall back to the focused element's frame (top-left), then its
        // position. It is not the caret, but it keeps the Picker attached to
        // the text field instead of jumping to the mouse.
        if let position = pointAttribute(element, kAXPositionAttribute),
           let size = sizeAttribute(element, kAXSizeAttribute), size.height > 0 {
            return CGRect(
                x: position.x,
                y: position.y,
                width: max(2, size.width),
                height: min(max(14, size.height), 80)
            )
        }

        if let position = pointAttribute(element, kAXPositionAttribute) {
            return CGRect(x: position.x, y: position.y, width: 2, height: 18)
        }

        return .zero
    }

    private static func bounds(for element: AXUIElement, range: AXValue) -> CGRect? {
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsRef
        ) == .success,
              let boundsRef,
              CFGetTypeID(boundsRef) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        guard rect.width.isFinite, rect.height.isFinite else { return nil }
        guard rect.height > 0 else { return nil }
        return rect
    }

    private static func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let valueRef,
              CFGetTypeID(valueRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let valueRef,
              CFGetTypeID(valueRef) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(valueRef as! AXValue, .cgSize, &size) else { return nil }
        return size
    }
}
