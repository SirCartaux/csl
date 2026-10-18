import AppKit

/// One result row: icon, title with match highlighting, dim path, selection bar.
final class ResultRowView: NSView {
    private var result: SearchResult?
    private var isSelected = false

    var rowIndex: Int = 0
    var menuProvider: ((Int) -> NSMenu?)?

    override var isFlipped: Bool { true }

    func configure(with result: SearchResult, selected: Bool) {
        self.result = result
        self.isSelected = selected
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(rowIndex)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let result else { return }

        if isSelected {
            PixelDraw.fill(bounds, Theme.bgSelected)
            PixelDraw.fill(CGRect(x: 0, y: 0, width: 3, height: bounds.height), Theme.accent)
        } else {
            PixelDraw.hLine(x: 52, y: bounds.maxY - 1, width: bounds.width - 52, color: Theme.line)
        }

        drawIcon(result)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let title = NSMutableAttributedString(
            string: result.title,
            attributes: [
                .font: Theme.display(15),
                .foregroundColor: Theme.text,
                .paragraphStyle: paragraph
            ]
        )
        for range in result.titleMatch where range.location + range.length <= title.length {
            title.addAttribute(.foregroundColor, value: Theme.accent, range: range)
        }
        title.draw(in: Layout.rowLabelRect(in: bounds))

        let subtitle = NSAttributedString(
            string: result.subtitle,
            attributes: [
                .font: Theme.display(9),
                .foregroundColor: isSelected ? Theme.textDim : Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
        subtitle.draw(in: Layout.rowSubtitleRect(in: bounds))

        if isSelected {
            PixelDraw.chevron(x: bounds.width - 21, y: 16, unit: 2, color: Theme.accent)
        }
    }

    private func drawIcon(_ result: SearchResult) {
        let box = CGRect(x: 18, y: 10, width: 22, height: 22)

        switch result.icon {
        case .file(let url):
            IconCache.shared.icon(for: url).draw(
                in: box,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )

        case .image(let url):
            if let image = IconCache.shared.image(at: url) {
                image.draw(
                    in: box,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
            } else {
                PixelGlyph.globe.image(size: 16, color: Theme.textDim).draw(
                    in: CGRect(x: box.minX + 3, y: box.minY + 3, width: 16, height: 16)
                )
            }

        case .glyph(let glyph):
            PixelDraw.fill(box, Theme.bgRaised)
            PixelDraw.frame(
                box,
                thickness: 1,
                color: isSelected ? Theme.accentDim : Theme.border,
                notch: 2
            )
            glyph.image(size: 16, color: isSelected ? Theme.accent : Theme.textDim).draw(
                in: CGRect(x: box.minX + 3, y: box.minY + 3, width: 16, height: 16),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }
    }
}
