import AppKit

/// Pure geometry for the panel. The view is flipped (origin top-left), so all
/// numbers below read like a design spec: header, field, list, footer.
enum Layout {
    static func panelRect(in bounds: CGRect) -> CGRect {
        CGRect(
            x: Theme.panelInset,
            y: Theme.panelInset,
            width: max(1, bounds.width - 2 * Theme.panelInset),
            height: max(1, bounds.height - 2 * Theme.panelInset)
        )
    }

    static func headerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: Theme.headerHeight)
    }

    static func fieldRect(in bounds: CGRect) -> CGRect {
        let header = headerRect(in: bounds)
        return CGRect(x: header.minX, y: header.maxY, width: header.width, height: Theme.fieldHeight)
    }

    static func footerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(
            x: panel.minX,
            y: panel.maxY - Theme.footerHeight,
            width: panel.width,
            height: Theme.footerHeight
        )
    }

    static func listRect(in bounds: CGRect) -> CGRect {
        let field = fieldRect(in: bounds)
        let footer = footerRect(in: bounds)
        return CGRect(
            x: field.minX,
            y: field.maxY,
            width: field.width,
            height: max(0, footer.minY - field.maxY)
        )
    }

    static func rowLabelRect(in bounds: CGRect) -> CGRect {
        CGRect(x: 52, y: 6, width: max(10, bounds.width - 52 - 30), height: 18)
    }

    static func rowSubtitleRect(in bounds: CGRect) -> CGRect {
        CGRect(x: 52, y: 26, width: max(10, bounds.width - 52 - 30), height: 12)
    }
}

/// Draws the window chrome: hard pixel shadow, notched border, header,
/// search prompt, empty state and footer hints. The animated halo lives in
/// GlowView on top of this view.
final class RootView: NSView {
    var query: String = ""
    var resultCount: Int = 0
    var isSearching: Bool = false
    var statusOverride: String? {
        didSet { needsDisplay = true }
    }
    var onOutsideClick: (() -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard Layout.panelRect(in: bounds).contains(point) else {
            onOutsideClick?()
            return
        }
        super.mouseDown(with: event)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let panel = Layout.panelRect(in: bounds)

        // 1. hard pixel drop shadow
        PixelDraw.fill(panel.offsetBy(dx: 4, dy: 4), Theme.shadow)

        // 2. surface
        PixelDraw.fill(panel, Theme.bg)

        // 3. border (the animated halo/rim lives in GlowView above this view)
        let borderColor = Theme.border.blended(withFraction: 0.16, of: Theme.accent) ?? Theme.border
        PixelDraw.frame(panel, thickness: 1, color: borderColor, notch: 3)

        drawHeader(panel: panel)
        drawSearchRow(panel: panel)
        drawList(panel: panel)
        drawFooter(panel: panel)
    }

    // MARK: - Header

    private func drawHeader(panel: CGRect) {
        let rect = Layout.headerRect(in: bounds)
        PixelDraw.fill(rect, Theme.bgRaised)
        PixelDraw.hLine(x: rect.minX, y: rect.maxY - 1, width: rect.width, color: Theme.line)

        PixelDraw.fill(CGRect(x: rect.minX + 18, y: rect.minY + 14, width: 4, height: 4), Theme.accent)

        let logoAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(15),
            .foregroundColor: Theme.accent
        ]
        let logoSize = ("CSL" as NSString).size(withAttributes: logoAttributes)
        ("CSL" as NSString).draw(
            in: CGRect(x: rect.minX + 30, y: rect.minY + 8, width: logoSize.width + 4, height: 18),
            withAttributes: logoAttributes
        )
        ("COMMAND SEARCH LAUNCHER" as NSString).draw(
            in: CGRect(
                x: rect.minX + 30 + logoSize.width + 10,
                y: rect.minY + 13,
                width: 260,
                height: 12
            ),
            withAttributes: [
                .font: Theme.display(7.5),
                .foregroundColor: Theme.textFaint
            ]
        )

        // hotkey hint on the right
        let keyText = "CMD + SPACE"
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8),
            .foregroundColor: Theme.textDim
        ]
        let keySize = (keyText as NSString).size(withAttributes: keyAttributes)
        let capRect = CGRect(
            x: rect.maxX - keySize.width - 20,
            y: rect.minY + 9,
            width: keySize.width + 12,
            height: 14
        )
        PixelDraw.frame(capRect, thickness: 1, color: Theme.border, notch: 2)
        (keyText as NSString).draw(
            in: CGRect(x: capRect.minX + 6, y: capRect.minY + 3, width: keySize.width + 2, height: 12),
            withAttributes: keyAttributes
        )
    }

    // MARK: - Search row

    private func drawSearchRow(panel: CGRect) {
        let rect = Layout.fieldRect(in: bounds)

        // prompt
        PixelDraw.chevron(x: rect.minX + 20, y: rect.minY + 20, unit: 3, color: Theme.accent)

        // baseline rule under the query
        PixelDraw.hLine(x: rect.minX, y: rect.maxY - 1, width: rect.width, color: Theme.line)
    }

    // MARK: - List / empty state

    private func drawList(panel: CGRect) {
        let rect = Layout.listRect(in: bounds)
        guard resultCount == 0 else { return }

        if isSearching {
            drawCentered(
                "SEARCHING",
                font: Theme.display(11),
                color: Theme.textDim,
                in: rect.offsetBy(dx: 0, dy: -6)
            )
            drawCentered(
                "HOLD ON A TICK",
                font: Theme.display(8),
                color: Theme.textFaint,
                in: rect.offsetBy(dx: 0, dy: 14)
            )
            return
        }

        if !query.isEmpty {
            drawCentered(
                "NO RESULTS",
                font: Theme.displayBold(13),
                color: Theme.text,
                in: rect.offsetBy(dx: 0, dy: -8)
            )
            drawCentered(
                "\"\(query)\" NOT FOUND",
                font: Theme.display(9),
                color: Theme.textFaint,
                in: rect.offsetBy(dx: 0, dy: 12)
            )
        }
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let height: CGFloat = 16
        (text as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
            withAttributes: attributes
        )
    }

    // MARK: - Footer

    private func drawFooter(panel: CGRect) {
        let rect = Layout.footerRect(in: bounds)
        PixelDraw.hLine(x: rect.minX, y: rect.minY, width: rect.width, color: Theme.line)

        var cursor: CGFloat = rect.minX + 18
        cursor = drawHint(key: "UP/DOWN", label: "NAVIGATE", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "ENTER", label: "OPEN", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "CMD+ENTER", label: "REVEAL", at: cursor, centerY: rect.midY)
        _ = drawHint(key: "ESC", label: "CLOSE", at: cursor, centerY: rect.midY)

        let status: String
        if let statusOverride {
            status = statusOverride
        } else if isSearching && resultCount == 0 {
            status = "SEARCHING"
        } else if resultCount > 0 {
            status = "\(resultCount) RESULTS"
        } else {
            status = ""
        }
        guard !status.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (status as NSString).draw(
            in: CGRect(x: rect.maxX - 220, y: rect.minY + 8, width: 202, height: 12),
            withAttributes: [
                .font: Theme.display(8.5),
                .foregroundColor: statusOverride != nil
                    ? Theme.accent
                    : (isSearching ? Theme.accentDim : Theme.textFaint),
                .paragraphStyle: paragraph
            ]
        )
    }

    @discardableResult
    private func drawHint(key: String, label: String, at x: CGFloat, centerY: CGFloat) -> CGFloat {
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8),
            .foregroundColor: Theme.textDim
        ]
        let keySize = (key as NSString).size(withAttributes: keyAttributes)
        let capRect = CGRect(
            x: x,
            y: centerY - 7,
            width: keySize.width + 10,
            height: 14
        ).integral
        PixelDraw.frame(capRect, thickness: 1, color: Theme.border, notch: 2)
        (key as NSString).draw(
            in: CGRect(x: capRect.minX + 5, y: capRect.minY + 3, width: keySize.width + 2, height: 10),
            withAttributes: keyAttributes
        )

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: Theme.textFaint
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        (label as NSString).draw(
            in: CGRect(x: capRect.maxX + 6, y: centerY - 6, width: labelSize.width + 2, height: 12),
            withAttributes: labelAttributes
        )
        return capRect.maxX + 6 + labelSize.width + 16
    }
}
