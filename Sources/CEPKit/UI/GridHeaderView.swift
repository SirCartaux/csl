import AppKit

/// The category / search title above the character grid. The skin tone
/// selector is a sibling on the right, so this view shrinks when it is shown.
final class GridHeaderView: NSView {
    var title = "RECENTLY USED" {
        didSet { needsDisplay = true }
    }
    var count = 0 {
        didSet { needsDisplay = true }
    }
    var isSearching = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: isSearching ? Theme.accent : Theme.textDim
        ]
        let titleText = title as NSString
        let titleSize = titleText.size(withAttributes: titleAttributes)
        titleText.draw(
            in: CGRect(x: 0, y: floor(bounds.midY - titleSize.height / 2), width: bounds.width - 70, height: titleSize.height),
            withAttributes: titleAttributes
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let countAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7.5),
            .foregroundColor: isSearching ? Theme.accentDim : Theme.textFaint,
            .paragraphStyle: paragraph
        ]
        let countText = "\(count)" as NSString
        countText.draw(
            in: CGRect(x: bounds.width - 70, y: floor(bounds.midY - 5), width: 70, height: 12),
            withAttributes: countAttributes
        )
    }
}
