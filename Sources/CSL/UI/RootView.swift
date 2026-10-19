import AppKit
import QuartzCore

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

    static func footerActivityRect(in bounds: CGRect) -> CGRect {
        let footer = footerRect(in: bounds)
        let size = Theme.ls(18)
        return CGRect(
            x: footer.maxX - Theme.ls(18) - size,
            y: footer.midY - size / 2,
            width: size,
            height: size
        )
    }

    static func headerClipboardRect(in bounds: CGRect) -> CGRect {
        let header = headerRect(in: bounds)
        let keyText = "CMD + SPACE"
        let keySize = (keyText as NSString).size(withAttributes: [.font: Theme.launcherDisplay(8)])
        let capX = header.maxX - keySize.width - Theme.ls(20)
        let width = Theme.ls(52)
        let height = Theme.ls(18)
        return CGRect(
            x: capX - Theme.ls(10) - width,
            y: header.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func footerProgressRect(in bounds: CGRect) -> CGRect {
        let footer = footerRect(in: bounds)
        let activity = footerActivityRect(in: bounds)
        let width = Theme.ls(150)
        return CGRect(
            x: activity.minX - Theme.ls(8) - width,
            y: footer.minY + Theme.ls(8),
            width: width,
            height: Theme.ls(12)
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
        let left = Theme.ls(52)
        let right = Theme.ls(30)
        return CGRect(x: left, y: Theme.ls(6), width: max(10, bounds.width - left - right), height: Theme.ls(18))
    }

    static func rowSubtitleRect(in bounds: CGRect) -> CGRect {
        let left = Theme.ls(52)
        let right = Theme.ls(30)
        return CGRect(x: left, y: Theme.ls(26), width: max(10, bounds.width - left - right), height: Theme.ls(12))
    }
}

/// Draws the window chrome: hard pixel shadow, notched border, header,
/// search prompt, empty state and footer hints. The animated halo lives in
/// GlowView on top of this view.
final class RootView: NSView {
    var query: String = ""
    var resultCount: Int = 0
    var isSearching: Bool = false
    var graphActive = false { didSet { needsDisplay = true } }
    var clipboardMode = false { didSet { needsDisplay = true } }
    var clipboardCount = 0 { didSet { needsDisplay = true } }
    var clipboardBytes = 0 { didSet { needsDisplay = true } }
    var clipboardCapacity = 30 * 1024 * 1024
    var calculatorActive = false {
        didSet { needsDisplay = true }
    }
    var indexProgress: (scanned: Int, total: Int)? {
        didSet { needsDisplay = true }
    }
    private var countFlashView: NSView?
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
        PixelDraw.fill(panel.offsetBy(dx: Theme.ls(4), dy: Theme.ls(4)), Theme.shadow)

        // 2. surface
        PixelDraw.fill(panel, Theme.bg)

        // 3. border (the animated halo/rim lives in GlowView above this view)
        let borderColor = Theme.border.blended(withFraction: 0.16, of: Theme.accent) ?? Theme.border
        PixelDraw.frame(panel, thickness: max(1, Theme.ls(1)), color: borderColor, notch: Theme.ls(3))

        drawHeader(panel: panel)
        drawSearchRow(panel: panel)
        drawList(panel: panel)
        drawFooter(panel: panel)
    }

    // MARK: - Header

    private func drawHeader(panel: CGRect) {
        let rect = Layout.headerRect(in: bounds)
        PixelDraw.fill(rect, Theme.bgRaised)
        PixelDraw.hLine(x: rect.minX, y: rect.maxY - Theme.ls(1), width: rect.width, color: Theme.line, thickness: max(1, Theme.ls(1)))

        PixelDraw.fill(
            CGRect(x: rect.minX + Theme.ls(18), y: rect.midY - Theme.ls(2), width: Theme.ls(4), height: Theme.ls(4)),
            Theme.accent
        )

        let logoAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplayBold(15),
            .foregroundColor: Theme.accent
        ]
        let logoSize = ("CSL" as NSString).size(withAttributes: logoAttributes)
        let logoRect = CGRect(
            x: rect.minX + Theme.ls(30),
            y: floor(rect.midY - logoSize.height / 2),
            width: logoSize.width + Theme.ls(4),
            height: logoSize.height
        )
        ("CSL" as NSString).draw(in: logoRect, withAttributes: logoAttributes)

        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplay(7.5),
            .foregroundColor: Theme.textFaint
        ]
        let subtitleSize = ("COMMAND SEARCH LAUNCHER" as NSString).size(withAttributes: subtitleAttributes)
        ("COMMAND SEARCH LAUNCHER" as NSString).draw(
            in: CGRect(
                x: rect.minX + Theme.ls(30) + logoSize.width + Theme.ls(10),
                y: floor(rect.midY - subtitleSize.height / 2),
                width: Theme.ls(260),
                height: subtitleSize.height
            ),
            withAttributes: subtitleAttributes
        )

        // hotkey hint on the right
        let keyText = "CMD + SPACE"
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplay(8),
            .foregroundColor: Theme.textDim
        ]
        let keySize = (keyText as NSString).size(withAttributes: keyAttributes)
        let capRect = CGRect(
            x: rect.maxX - keySize.width - Theme.ls(20),
            y: rect.minY + Theme.ls(9),
            width: keySize.width + Theme.ls(12),
            height: Theme.ls(14)
        )
        PixelDraw.frame(capRect, thickness: max(1, Theme.ls(1)), color: Theme.border, notch: Theme.ls(2))
        (keyText as NSString).draw(
            in: CGRect(
                x: floor(capRect.midX - keySize.width / 2),
                y: floor(capRect.midY - keySize.height / 2),
                width: keySize.width + Theme.ls(2),
                height: keySize.height
            ),
            withAttributes: keyAttributes
        )
    }

    // MARK: - Search row

    private func drawSearchRow(panel: CGRect) {
        let rect = Layout.fieldRect(in: bounds)

        // The prompt chevron is a SearchPromptView so it can pop and glow.

        // baseline rule under the query
        PixelDraw.hLine(x: rect.minX, y: rect.maxY - Theme.ls(1), width: rect.width, color: Theme.line, thickness: max(1, Theme.ls(1)))
    }

    // MARK: - List / empty state

    private func drawList(panel: CGRect) {
        let rect = Layout.listRect(in: bounds)
        guard !graphActive, !clipboardMode, resultCount == 0 else { return }

        if isSearching || indexProgress != nil {
            drawCentered(
                "SEARCHING",
                font: Theme.launcherDisplay(11),
                color: Theme.textDim,
                in: rect.offsetBy(dx: 0, dy: -Theme.ls(6))
            )
            drawCentered(
                "HOLD ON A TICK",
                font: Theme.launcherDisplay(8),
                color: Theme.textFaint,
                in: rect.offsetBy(dx: 0, dy: Theme.ls(14))
            )
            return
        }

        if calculatorActive {
            drawCentered(
                "CALCULATION",
                font: Theme.launcherDisplay(9),
                color: Theme.textFaint,
                in: rect
            )
            return
        }

        if !query.isEmpty {
            drawCentered(
                "NO RESULTS",
                font: Theme.launcherDisplayBold(13),
                color: Theme.text,
                in: rect.offsetBy(dx: 0, dy: -Theme.ls(8))
            )
            drawCentered(
                "\"\(query)\" NOT FOUND",
                font: Theme.launcherDisplay(9),
                color: Theme.textFaint,
                in: rect.offsetBy(dx: 0, dy: Theme.ls(12))
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
        let height = Theme.ls(16)
        (text as NSString).draw(
            in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
            withAttributes: attributes
        )
    }

    // MARK: - Footer

    private func drawFooter(panel: CGRect) {
        let rect = Layout.footerRect(in: bounds)
        PixelDraw.hLine(x: rect.minX, y: rect.minY, width: rect.width, color: Theme.line, thickness: max(1, Theme.ls(1)))

        if graphActive {
            var x = rect.minX + Theme.ls(18)
            x = drawHint(key: "SCROLL", label: "ZOOM", at: x, centerY: rect.midY)
            x = drawHint(key: "DRAG", label: "PAN", at: x, centerY: rect.midY)
            x = drawHint(key: "ENTER", label: "AUTO", at: x, centerY: rect.midY)
            _ = drawHint(key: "ESC", label: "CLOSE", at: x, centerY: rect.midY)
            return
        }
        if clipboardMode {
            var x = rect.minX + Theme.ls(18)
            x = drawHint(key: "UP/DOWN", label: "BROWSE", at: x, centerY: rect.midY)
            x = drawHint(key: "ENTER", label: "COPY", at: x, centerY: rect.midY)
            x = drawHint(key: "CMD+P", label: "PIN", at: x, centerY: rect.midY)
            x = drawHint(key: "CMD+DEL", label: "DELETE", at: x, centerY: rect.midY)
            _ = drawHint(key: "ESC", label: "BACK", at: x, centerY: rect.midY)

            if let statusOverride {
                drawStatus(statusOverride, in: CGRect(
                    x: rect.maxX - Theme.ls(240),
                    y: rect.minY + Theme.ls(8),
                    width: Theme.ls(222),
                    height: Theme.ls(12)
                ), color: Theme.accent)
                return
            }

            let bytes = ByteCountFormatter.string(fromByteCount: Int64(clipboardBytes), countStyle: .memory)
            let capacity = ByteCountFormatter.string(fromByteCount: Int64(clipboardCapacity), countStyle: .memory)
            let countText = "\(clipboardCount) \(clipboardCount == 1 ? "ITEM" : "ITEMS")  ·  \(bytes)/\(capacity)"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            (countText as NSString).draw(
                in: CGRect(x: rect.maxX - Theme.ls(240), y: rect.minY + Theme.ls(8), width: Theme.ls(222), height: Theme.ls(12)),
                withAttributes: [
                    .font: Theme.launcherDisplay(8),
                    .foregroundColor: Theme.textFaint,
                    .paragraphStyle: paragraph
                ]
            )
            return
        }
        var cursor: CGFloat = rect.minX + Theme.ls(18)
        cursor = drawHint(key: "UP/DOWN", label: "NAVIGATE", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "ENTER", label: "OPEN", at: cursor, centerY: rect.midY)
        cursor = drawHint(key: "CMD+ENTER", label: "REVEAL", at: cursor, centerY: rect.midY)
        _ = drawHint(key: "ESC", label: "CLOSE", at: cursor, centerY: rect.midY)

        let activity = Layout.footerActivityRect(in: bounds)
        let statusRight = indexProgress != nil
            ? activity.minX - Theme.ls(8)
            : rect.maxX - Theme.ls(18)
        let statusRect = CGRect(
            x: statusRight - Theme.ls(202),
            y: rect.minY + Theme.ls(8),
            width: Theme.ls(202),
            height: Theme.ls(12)
        )

        if let statusOverride {
            drawStatus(statusOverride, in: statusRect, color: Theme.accent)
        } else if let progress = indexProgress, progress.total > 0 {
            let progressText = "SCAN \(CSLFormat.compact(progress.scanned))/\(CSLFormat.compact(progress.total))"
            drawStatus(progressText, in: Layout.footerProgressRect(in: bounds), color: Theme.accentDim)
        } else {
            let status: String
            if isSearching && resultCount == 0 {
                status = "SEARCHING"
            } else if resultCount > 0 {
                status = "\(resultCount) RESULTS"
            } else {
                status = ""
            }
            guard !status.isEmpty else { return }
            drawStatus(status, in: statusRect, color: isSearching ? Theme.accentDim : Theme.textFaint)
        }
    }

    /// Briefly overlay the result count in green, then fade back to the
    /// normal footer colour.
    func flashResultCount() {
        guard resultCount > 0, statusOverride == nil else { return }
        countFlashView?.removeFromSuperview()

        let footer = Layout.footerRect(in: bounds)
        let activity = Layout.footerActivityRect(in: bounds)
        let statusRight = indexProgress != nil
            ? activity.minX - Theme.ls(8)
            : footer.maxX - Theme.ls(18)
        let rect = CGRect(
            x: statusRight - Theme.ls(202),
            y: footer.minY + Theme.ls(8),
            width: Theme.ls(202),
            height: Theme.ls(12)
        )

        let flash = FooterFlashView(frame: rect, text: "\(resultCount) RESULTS")
        flash.wantsLayer = true
        flash.layer?.shadowColor = Theme.success.cgColor
        flash.layer?.shadowOpacity = 0.9
        flash.layer?.shadowRadius = Theme.ls(5)
        flash.layer?.shadowOffset = .zero
        addSubview(flash)
        countFlashView = flash

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.65
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        flash.layer?.add(fade, forKey: "countFlash")
        flash.layer?.opacity = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self, weak flash] in
            guard let flash else { return }
            if self?.countFlashView === flash {
                self?.countFlashView = nil
            }
            flash.removeFromSuperview()
        }
    }

    private func drawStatus(_ text: String, in rect: CGRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: Theme.launcherDisplay(8.5),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    @discardableResult
    private func drawHint(key: String, label: String, at x: CGFloat, centerY: CGFloat) -> CGFloat {
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplay(8),
            .foregroundColor: Theme.textDim
        ]
        let keySize = (key as NSString).size(withAttributes: keyAttributes)
        let capRect = CGRect(
            x: x,
            y: centerY - Theme.ls(7),
            width: keySize.width + Theme.ls(10),
            height: Theme.ls(14)
        ).integral
        PixelDraw.frame(capRect, thickness: max(1, Theme.ls(1)), color: Theme.border, notch: Theme.ls(2))
        (key as NSString).draw(
            in: CGRect(x: capRect.minX + Theme.ls(5), y: capRect.minY + Theme.ls(3), width: keySize.width + Theme.ls(2), height: Theme.ls(10)),
            withAttributes: keyAttributes
        )

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.launcherDisplay(8.5),
            .foregroundColor: Theme.textFaint
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        (label as NSString).draw(
            in: CGRect(x: capRect.maxX + Theme.ls(6), y: centerY - Theme.ls(6), width: labelSize.width + Theme.ls(2), height: Theme.ls(12)),
            withAttributes: labelAttributes
        )
        return capRect.maxX + Theme.ls(6) + labelSize.width + Theme.ls(16)
    }
}


private final class FooterFlashView: NSView {
    private let text: String

    init(frame: NSRect, text: String) {
        self.text = text
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        (text as NSString).draw(
            in: bounds,
            withAttributes: [
                .font: Theme.launcherDisplay(8.5),
                .foregroundColor: Theme.success,
                .paragraphStyle: paragraph
            ]
        )
    }
}
