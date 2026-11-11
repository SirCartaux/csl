import AppKit

/// A visual suffix only. It never changes the native field's text or caret.
final class SearchCompletionView: NSView {
    var suffix = "" { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func suffix(for input: String, completion: String) -> String? {
        guard !input.isEmpty,
              let range = completion.range(of: input, options: [.anchored, .caseInsensitive]),
              range.upperBound < completion.endIndex else { return nil }
        return String(completion[range.upperBound...])
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplay(20),
            .foregroundColor: Theme.textFaint.withAlphaComponent(0.65),
            .paragraphStyle: paragraph
        ]
        let size = (suffix as NSString).size(withAttributes: attributes)
        (suffix as NSString).draw(in: CGRect(x: 0, y: floor((bounds.height - size.height) / 2),
                                            width: bounds.width, height: size.height), withAttributes: attributes)
    }
}
