import AppKit

/// The left rail: twelve category rows with emoji icons, pixel labels and
/// recent/favorite counts. Selection uses the same amber bar as CSL's rows.
final class CategorySidebarView: NSView {
    var onSelect: ((PickerCategory) -> Void)?
    var selected: PickerCategory = .recent {
        didSet { needsDisplay = true }
    }
    var counts: [PickerCategory: Int] = [:] {
        didSet { needsDisplay = true }
    }

    private var hovered: PickerCategory?
    private var tracking: NSTrackingArea?

    private let categories = PickerCategory.allCases
    private let rowHeight = Theme.sidebarRowHeight
    private let topPadding = Theme.sidebarPadding

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        tracking = area
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let row = category(at: convert(event.locationInWindow, from: nil))
        guard row != hovered else { return }
        hovered = row
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let category = category(at: convert(event.locationInWindow, from: nil)) else { return }
        selected = category
        onSelect?(category)
    }

    private func category(at point: CGPoint) -> PickerCategory? {
        guard bounds.contains(point) else { return nil }
        let index = Int(floor((point.y - topPadding) / rowHeight))
        guard index >= 0, index < categories.count else { return nil }
        return categories[index]
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, category) in categories.enumerated() {
            let row = CGRect(
                x: 0,
                y: topPadding + CGFloat(index) * rowHeight,
                width: bounds.width,
                height: rowHeight
            )
            guard row.intersects(dirtyRect) else { continue }
            draw(category: category, in: row, index: index)
        }
    }

    private func draw(category: PickerCategory, in row: CGRect, index: Int) {
        let isSelected = category == selected
        let isHovered = category == hovered

        if isSelected {
            PixelDraw.fill(row, Theme.bgSelected)
            PixelDraw.fill(
                CGRect(x: 0, y: row.minY + 3, width: 2, height: row.height - 6),
                Theme.accent
            )
        } else if isHovered {
            PixelDraw.fill(row, Theme.bgRaised.withAlphaComponent(0.75))
        }

        let iconRect = CGRect(x: 12, y: row.midY - 8, width: 16, height: 16)
        drawIcon(category.icon, isText: category.iconIsText, selected: isSelected, in: iconRect)

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7.5),
            .foregroundColor: isSelected ? Theme.accent : (isHovered ? Theme.text : Theme.textDim)
        ]
        (category.title as NSString).draw(
            in: CGRect(x: 34, y: floor(row.midY - 5), width: 56, height: 12),
            withAttributes: labelAttributes
        )

        if let count = counts[category], count > 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            let countAttributes: [NSAttributedString.Key: Any] = [
                .font: Theme.display(6.5),
                .foregroundColor: isSelected ? Theme.accentDim : Theme.textFaint,
                .paragraphStyle: paragraph
            ]
            ("\(count)" as NSString).draw(
                in: CGRect(x: bounds.width - 46, y: floor(row.midY - 5), width: 30, height: 10),
                withAttributes: countAttributes
            )
        }

        if isSelected {
            PixelDraw.chevron(
                x: bounds.width - 13,
                y: floor(row.midY - 2.5),
                unit: 1,
                color: Theme.accent
            )
        }

        if index < categories.count - 1 {
            PixelDraw.hLine(
                x: 12,
                y: row.maxY - 1,
                width: bounds.width - 24,
                color: Theme.line.withAlphaComponent(0.55)
            )
        }
    }

    private func drawIcon(_ icon: String, isText: Bool, selected: Bool, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: isText
                ? NSFont.systemFont(ofSize: 13, weight: .medium)
                : Theme.sidebarEmojiFont,
            .foregroundColor: selected
                ? (isText ? Theme.accent : NSColor.white)
                : (isText ? Theme.textDim : NSColor.white)
        ]
        let size = (icon as NSString).size(withAttributes: attributes)
        (icon as NSString).draw(
            in: CGRect(
                x: rect.midX - size.width / 2,
                y: rect.midY - size.height / 2,
                width: size.width + 2,
                height: size.height
            ),
            withAttributes: attributes
        )
    }
}
