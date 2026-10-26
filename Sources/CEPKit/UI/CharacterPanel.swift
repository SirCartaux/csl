import AppKit

/// Borderless, always-on-top panel that can become key without activating the
/// app. The previous application stays frontmost, so `postToPid` can type into
/// its focused text field while the picker keeps keyboard focus for search.
final class CharacterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Theme.windowWidth,
                height: Theme.windowHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        worksWhenModal = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
