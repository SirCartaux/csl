import AppKit

final class SettingsSidebarView: NSView {
    private let items: [(title: String, glyph: PixelGlyph)] = [
        ("ORDNER", .folder),
        ("IGNORIEREN", .ban),
        ("WEBSITES", .globe),
        ("ANIMATION", .sparkle),
        ("ALLGEMEIN", .gear)
    ]

    private let itemHeight: CGFloat = 42
    private let itemGap: CGFloat = 2
    private let topInset: CGFloat = 18

    var selectedIndex: Int = 0 {
        didSet { needsDisplay = true }
    }

    var onSelect: ((Int) -> Void)?

    private var hoverIndex: Int?

    override var isFlipped: Bool { true }

    private func itemRect(at index: Int) -> CGRect {
        CGRect(
            x: 0,
            y: topInset + CGFloat(index) * (itemHeight + itemGap),
            width: bounds.width,
            height: itemHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.fill(bounds, Theme.bgRaised)
        PixelDraw.fill(
            CGRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height),
            Theme.line
        )

        for (index, item) in items.enumerated() {
            let rect = itemRect(at: index)
            let selected = index == selectedIndex
            let hovered = index == hoverIndex

            if selected {
                PixelDraw.fill(rect, Theme.bgSelected)
                PixelDraw.fill(
                    CGRect(x: 0, y: rect.minY + 6, width: 3, height: rect.height - 12),
                    Theme.accent
                )
            } else if hovered {
                PixelDraw.fill(rect, Theme.bgSelected.withAlphaComponent(0.45))
            }

            let tint = selected ? Theme.accent : (hovered ? Theme.text : Theme.textDim)
            let icon = item.glyph.image(size: 18, color: tint)
            icon.draw(
                in: CGRect(x: 20, y: rect.minY + 12, width: 18, height: 18),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.none]
            )

            (item.title as NSString).draw(
                in: CGRect(x: 48, y: rect.minY + 13, width: rect.width - 58, height: 16),
                withAttributes: [
                    .font: Theme.display(10),
                    .foregroundColor: selected ? Theme.text : Theme.textDim
                ]
            )
        }

        // footer
        PixelDraw.hLine(x: 18, y: bounds.maxY - 52, width: bounds.width - 36, color: Theme.line)
        ("v0.3.0" as NSString).draw(
            in: CGRect(x: 20, y: bounds.maxY - 42, width: 80, height: 12),
            withAttributes: [
                .font: Theme.display(8.5),
                .foregroundColor: Theme.textFaint
            ]
        )
        ("SILKSCREEN / OFL" as NSString).draw(
            in: CGRect(x: 20, y: bounds.maxY - 28, width: bounds.width - 30, height: 12),
            withAttributes: [
                .font: Theme.display(7),
                .foregroundColor: Theme.textFaint
            ]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = items.indices.first { itemRect(at: $0).contains(point) }
        if index != hoverIndex {
            hoverIndex = index
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = items.indices.first(where: { itemRect(at: $0).contains(point) }) else {
            return
        }
        selectedIndex = index
        onSelect?(index)
    }
}
