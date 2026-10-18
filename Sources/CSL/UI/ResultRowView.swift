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
            PixelDraw.fill(CGRect(x: 0, y: 0, width: Theme.ls(3), height: bounds.height), Theme.accent)
        } else {
            PixelDraw.hLine(x: Theme.ls(52), y: bounds.maxY - Theme.ls(1), width: bounds.width - Theme.ls(52), color: Theme.line, thickness: max(1, Theme.ls(1)))
        }

        drawIcon(result)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let title = NSMutableAttributedString(
            string: result.title,
            attributes: [
                .font: Theme.launcherDisplay(15),
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
                .font: Theme.launcherDisplay(9),
                .foregroundColor: isSelected ? Theme.textDim : Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
        subtitle.draw(in: Layout.rowSubtitleRect(in: bounds))

        if isSelected {
            PixelDraw.chevron(x: bounds.width - Theme.ls(21), y: Theme.ls(16), unit: Theme.ls(2), color: Theme.accent)
        }
    }

    private func drawIcon(_ result: SearchResult) {
        let box = CGRect(x: Theme.ls(18), y: Theme.ls(10), width: Theme.ls(22), height: Theme.ls(22))

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
                PixelGlyph.globe.image(size: Theme.ls(16), color: Theme.textDim).draw(
                    in: CGRect(x: box.minX + Theme.ls(3), y: box.minY + Theme.ls(3), width: Theme.ls(16), height: Theme.ls(16))
                )
            }

        case .glyph(let glyph):
            PixelDraw.fill(box, Theme.bgRaised)
            PixelDraw.frame(
                box,
                thickness: max(1, Theme.ls(1)),
                color: isSelected ? Theme.accentDim : Theme.border,
                notch: Theme.ls(2)
            )
            glyph.image(size: Theme.ls(16), color: isSelected ? Theme.accent : Theme.textDim).draw(
                in: CGRect(x: box.minX + Theme.ls(3), y: box.minY + Theme.ls(3), width: Theme.ls(16), height: Theme.ls(16)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }
    }
}
