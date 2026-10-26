import AppKit
import QuartzCore

/// Pure geometry for the picker. The view is flipped (origin top-left), so
/// every number below reads like a design spec: header, field, body, footer.
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

    static func bodyRect(in bounds: CGRect) -> CGRect {
        let field = fieldRect(in: bounds)
        let footer = footerRect(in: bounds)
        return CGRect(
            x: field.minX,
            y: field.maxY,
            width: field.width,
            height: max(0, footer.minY - field.maxY)
        )
    }

    static func sidebarRect(in bounds: CGRect) -> CGRect {
        var body = bodyRect(in: bounds)
        body.size.width = Theme.sidebarWidth
        return body
    }

    static func gridHeaderRect(in bounds: CGRect) -> CGRect {
        let body = bodyRect(in: bounds)
        return CGRect(
            x: body.minX + Theme.sidebarWidth,
            y: body.minY,
            width: max(0, body.width - Theme.sidebarWidth),
            height: Theme.gridHeaderHeight
        )
    }

    static func gridRect(in bounds: CGRect) -> CGRect {
        let body = bodyRect(in: bounds)
        let header = gridHeaderRect(in: bounds)
        return CGRect(
            x: body.minX + Theme.sidebarWidth,
            y: header.maxY,
            width: max(0, body.width - Theme.sidebarWidth),
            height: max(0, body.maxY - header.maxY)
        )
    }

    static func gridContentWidth(in bounds: CGRect) -> CGFloat {
        max(10, gridRect(in: bounds).width - 2 * Theme.gridPadding)
    }

    static func skinToneRect(in bounds: CGRect) -> CGRect {
        let header = gridHeaderRect(in: bounds)
        let width: CGFloat = 112
        let height: CGFloat = 18
        return CGRect(
            x: header.maxX - Theme.gridPadding - width,
            y: header.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func searchFieldRect(in bounds: CGRect) -> CGRect {
        let field = fieldRect(in: bounds)
        return CGRect(
            x: field.minX + 44,
            y: field.minY + 12,
            width: field.width - 44 - 46,
            height: field.height - 22
        )
    }

    static func clearButtonRect(in bounds: CGRect) -> CGRect {
        let field = fieldRect(in: bounds)
        return CGRect(x: field.maxX - 34, y: field.midY - 8, width: 16, height: 16)
    }

    static func promptCenter(in bounds: CGRect) -> CGPoint {
        let field = fieldRect(in: bounds)
        return CGPoint(x: field.minX + 22, y: field.midY)
    }
}

/// Draws the window chrome: hard pixel shadow, notched border, header, field
/// rule, sidebar/grid surfaces and footer hints. The animated halo lives in
/// GlowView above this view.
final class PickerRootView: NSView {
    var logoText = "CEP" {
        didSet { needsDisplay = true }
    }
    var categoryTitle = "RECENTLY USED"
    var resultCount = 0
    var isSearching = false
    var isLoaded = true
    var query = ""
    var selectedName = ""
    var statusOverride: String? {
        didSet { needsDisplay = true }
    }
    var statusColor: NSColor = Theme.accent
    var onOutsideClick: (() -> Void)?

    private var statusWork: DispatchWorkItem?

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

    func flashStatus(_ text: String, color: NSColor, duration: TimeInterval = 0.95) {
        statusWork?.cancel()
        statusOverride = text
        statusColor = color
        let work = DispatchWorkItem { [weak self] in
            self?.statusOverride = nil
            self?.needsDisplay = true
        }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
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
        drawField(panel: panel)
        drawBody(panel: panel)
        drawFooter(panel: panel)
    }

    // MARK: - Header

    private func drawHeader(panel: CGRect) {
        let rect = Layout.headerRect(in: bounds)
        PixelDraw.fill(rect, Theme.bgRaised)
        PixelDraw.hLine(x: rect.minX, y: rect.maxY - 1, width: rect.width, color: Theme.line)

        PixelDraw.fill(
            CGRect(x: rect.minX + 18, y: rect.midY - 2, width: 4, height: 4),
            Theme.accent
        )

        let logoAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(15),
            .foregroundColor: Theme.accent
        ]
        let logo = logoText as NSString
        let logoSize = logo.size(withAttributes: logoAttributes)
        let logoRect = CGRect(
            x: rect.minX + 30,
            y: floor(rect.midY - logoSize.height / 2),
            width: logoSize.width + 4,
            height: logoSize.height
        )
        logo.draw(in: logoRect, withAttributes: logoAttributes)

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7.5),
            .foregroundColor: Theme.textFaint
        ]
        let subtitle = "CHARACTER PICKER"
        let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
        (subtitle as NSString).draw(
            in: CGRect(
                x: rect.minX + 30 + logoSize.width + 10,
                y: floor(rect.midY - subtitleSize.height / 2),
                width: 240,
                height: subtitleSize.height
            ),
            withAttributes: subtitleAttributes
        )

        // Right side: `FN  GLOBE KEY` keycap.
        let keyText = "FN"
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8),
            .foregroundColor: Theme.textDim
        ]
        let keySize = (keyText as NSString).size(withAttributes: keyAttributes)
        let capRect = CGRect(
            x: rect.maxX - keySize.width - 34,
            y: rect.minY + 9,
            width: keySize.width + 16,
            height: 14
        )
        PixelDraw.frame(capRect, thickness: 1, color: Theme.border, notch: 2)
        (keyText as NSString).draw(
            in: CGRect(
                x: floor(capRect.midX - keySize.width / 2),
                y: floor(capRect.midY - keySize.height / 2),
                width: keySize.width + 2,
                height: keySize.height
            ),
            withAttributes: keyAttributes
        )

        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(7.5),
            .foregroundColor: Theme.textFaint
        ]
        let hint = "GLOBE KEY"
        let hintSize = (hint as NSString).size(withAttributes: hintAttributes)
        (hint as NSString).draw(
            in: CGRect(
                x: floor(capRect.minX - hintSize.width - 8),
                y: floor(rect.midY - hintSize.height / 2),
                width: hintSize.width + 2,
                height: hintSize.height
            ),
            withAttributes: hintAttributes
        )
    }

    // MARK: - Field

    private func drawField(panel: CGRect) {
        let rect = Layout.fieldRect(in: bounds)
        PixelDraw.hLine(
            x: rect.minX,
            y: rect.maxY - 1,
            width: rect.width,
            color: Theme.line
        )
    }

    // MARK: - Body

    private func drawBody(panel: CGRect) {
        let sidebar = Layout.sidebarRect(in: bounds)
        PixelDraw.fill(sidebar, Theme.bgRaised)
        PixelDraw.vLine(
            x: sidebar.maxX - 1,
            y: sidebar.minY,
            height: sidebar.height,
            color: Theme.line
        )

        let gridHeader = Layout.gridHeaderRect(in: bounds)
        PixelDraw.hLine(
            x: gridHeader.minX,
            y: gridHeader.maxY - 1,
            width: gridHeader.width,
            color: Theme.line
        )

        // A very quiet dotted rule under the category header, so the grid
        // still reads as a pixel list rather than a flat canvas.
        PixelDraw.dottedLine(
            x: gridHeader.minX + Theme.gridPadding,
            y: gridHeader.maxY - 5,
            width: max(0, gridHeader.width - 2 * Theme.gridPadding),
            color: Theme.line.withAlphaComponent(0.55),
            step: 5
        )

    }

    // MARK: - Footer

    private func drawFooter(panel: CGRect) {
        let rect = Layout.footerRect(in: bounds)
        PixelDraw.hLine(x: rect.minX, y: rect.minY, width: rect.width, color: Theme.line)

        var cursor = rect.minX + 18
        cursor = drawHint(key: "UP/DOWN", label: "NAVIGATE", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "ENTER", label: "INSERT", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "CMD+CLICK", label: "PIN", at: cursor, centerY: rect.midY)
        _ = drawHint(key: "ESC", label: "CLOSE", at: cursor, centerY: rect.midY)

        let statusRect = CGRect(
            x: rect.maxX - 252,
            y: rect.minY + 8,
            width: 234,
            height: 12
        )

        if let statusOverride {
            drawStatus(statusOverride, in: statusRect, color: statusColor)
            return
        }

        if !selectedName.isEmpty {
            drawStatus(selectedName.uppercased(), in: statusRect, color: Theme.textFaint)
            return
        }

        let countText: String
        if isSearching {
            countText = resultCount == 1 ? "1 MATCH" : "\(resultCount) MATCHES"
        } else if resultCount == 1 {
            countText = "1 ITEM"
        } else {
            countText = "\(resultCount) ITEMS"
        }
        drawStatus(countText, in: statusRect, color: Theme.textFaint)
    }

    private func drawStatus(_ text: String, in rect: CGRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(
            in: rect,
            withAttributes: attributes
        )
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY - 8, width: rect.width, height: 16),
            withAttributes: attributes
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
            in: CGRect(
                x: capRect.minX + 5,
                y: capRect.minY + 3,
                width: keySize.width + 2,
                height: 10
            ),
            withAttributes: keyAttributes
        )

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: Theme.textFaint
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        (label as NSString).draw(
            in: CGRect(
                x: capRect.maxX + 6,
                y: centerY - 6,
                width: labelSize.width + 2,
                height: 12
            ),
            withAttributes: labelAttributes
        )
        return capRect.maxX + 6 + labelSize.width + 14
    }
}
