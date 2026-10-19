import AppKit

/// Draws the empty-query placeholder centered in the search row. The native
/// NSTextField placeholder is top-aligned in its cell, which looks off in the
/// taller launcher field.
final class SearchPlaceholderView: NSView {
    var text = "TYPE TO SEARCH" {
        didSet { needsDisplay = true }
    }

    private let leftInset: CGFloat = 4

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplay(15),
            .foregroundColor: Theme.textFaint
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(
            x: leftInset,
            y: (bounds.height - size.height) / 2,
            width: max(1, bounds.width - leftInset),
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
