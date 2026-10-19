import AppKit

final class ClipboardEntryRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("clipboard-entry")

    private var entry: ClipboardEntry?
    private var isSelected = false
    private var isHovered = false
    private var thumbnail: NSImage?
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    func configure(with entry: ClipboardEntry, selected: Bool, thumbnail: NSImage?) {
        self.entry = entry
        self.isSelected = selected
        self.thumbnail = thumbnail
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let entry else { return }

        if isSelected {
            PixelDraw.fill(bounds, Theme.bgSelected)
            PixelDraw.fill(CGRect(x: 0, y: 0, width: 3, height: bounds.height), Theme.accent)
        } else if isHovered {
            PixelDraw.fill(bounds, Theme.bgRaised)
        } else {
            PixelDraw.hLine(x: 18, y: bounds.maxY - 1, width: bounds.width - 36, color: Theme.line)
        }

        let tile = CGRect(x: 18, y: 11, width: 46, height: 46)
        drawTile(entry: entry, in: tile)

        let rightMeta: CGFloat = 150
        let textWidth = max(10, bounds.width - tile.maxX - 18 - rightMeta)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let title = NSAttributedString(
            string: entry.title,
            attributes: [
                .font: Theme.displayBold(11.5),
                .foregroundColor: isSelected ? Theme.accent : Theme.text,
                .paragraphStyle: paragraph
            ]
        )
        title.draw(in: CGRect(x: tile.maxX + 14, y: 9, width: textWidth, height: 16))

        let subtitle = NSAttributedString(
            string: entry.subtitle.replacingOccurrences(of: "\n", with: "  ·  "),
            attributes: [
                .font: Theme.display(8.5),
                .foregroundColor: isSelected ? Theme.textDim : Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
        subtitle.draw(in: CGRect(x: tile.maxX + 14, y: 27, width: textWidth, height: 12))

        let sourceText = entry.sourceApp.map { "FROM \($0.uppercased())" }
            ?? (entry.kind == .image ? "CLIPBOARD IMAGE" : entry.kind.label)
        (sourceText as NSString).draw(
            in: CGRect(x: tile.maxX + 14, y: 45, width: textWidth, height: 10),
            withAttributes: [
                .font: Theme.display(6.8),
                .foregroundColor: Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )

        let right = bounds.width - 18
        let metaWidth: CGFloat = 132
        let time = Self.relativeTime(entry.createdAt)
        let size = ByteCountFormatter.string(fromByteCount: Int64(entry.byteSize), countStyle: .memory)
        let type = entry.kind.label + (entry.pinned ? "  ·  PIN" : "")
        let metaColor = entry.pinned ? Theme.success : Theme.textFaint

        drawRight(time, x: right - metaWidth, width: metaWidth, y: 10, color: Theme.textDim, bold: true)
        drawRight(size, x: right - metaWidth, width: metaWidth, y: 27, color: Theme.textFaint, bold: false)
        drawRight(type, x: right - metaWidth, width: metaWidth, y: 44, color: metaColor, bold: false)

        if entry.pinned {
            PixelDraw.fill(CGRect(x: right - 2, y: 47, width: 2, height: 3), Theme.success)
        }
    }

    private func drawTile(entry: ClipboardEntry, in tile: CGRect) {
        PixelDraw.fill(tile, Theme.bgRaised)
        PixelDraw.frame(tile, thickness: 1, color: isSelected ? Theme.accentDim : Theme.border, notch: 2)

        switch entry.kind {
        case .image:
            if let thumbnail {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: tile.insetBy(dx: 2, dy: 2)).addClip()
                let source = Self.aspectFillSource(thumbnail.size, in: tile.insetBy(dx: 2, dy: 2))
                thumbnail.draw(
                    in: tile.insetBy(dx: 2, dy: 2),
                    from: source,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high]
                )
                NSGraphicsContext.restoreGraphicsState()
            } else {
                PixelGlyph.clipboard.image(size: 18, color: Theme.textDim)
                    .draw(in: CGRect(x: tile.midX - 9, y: tile.midY - 9, width: 18, height: 18))
            }

        case .files:
            let path = entry.filePaths?.first ?? ""
            IconCache.shared.icon(for: URL(fileURLWithPath: path)).draw(
                in: tile.insetBy(dx: 6, dy: 6),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )

        case .link:
            PixelGlyph.globe.image(size: 18, color: isSelected ? Theme.accent : Theme.textDim)
                .draw(in: CGRect(x: tile.midX - 9, y: tile.midY - 9, width: 18, height: 18))

        case .text:
            PixelGlyph.clipboard.image(size: 18, color: isSelected ? Theme.accent : Theme.textDim)
                .draw(in: CGRect(x: tile.midX - 9, y: tile.midY - 9, width: 18, height: 18))
        }
    }

    private func drawRight(
        _ text: String,
        x: CGFloat,
        width: CGFloat,
        y: CGFloat,
        color: NSColor,
        bold: Bool
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: 10),
            withAttributes: [
                .font: bold ? Theme.displayBold(7.5) : Theme.display(7.5),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func aspectFillSource(_ size: NSSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let width = rect.width / scale
        let height = rect.height / scale
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    private static func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 45 { return "JUST NOW" }
        if seconds < 3600 { return "\(Int(seconds / 60)) MIN AGO" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) H AGO" }
        if seconds < 86400 * 7 { return "\(Int(seconds / 86400)) D AGO" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter.string(from: date)
    }
}
