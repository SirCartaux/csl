import AppKit

/// Places the picker above the text cursor, attached like a popover and
/// clamped to the screen. AX coordinates use a top-left origin; AppKit uses
/// bottom-left, so the caret is converted through the primary display height.
enum PickerPositioner {
    static func frame(anchor: CaretAnchor?, windowSize: CGSize) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
        var caret: CGRect

        if let anchor,
           anchor.axRect.width.isFinite,
           anchor.axRect.height.isFinite,
           anchor.axRect.width > 0,
           anchor.axRect.height > 0,
           anchor.axRect.width < 2200,
           anchor.axRect.height < 400,
           anchor.axRect.minX > -20_000,
           anchor.axRect.minY > -20_000 {
            caret = CGRect(
                x: anchor.axRect.minX,
                y: primaryHeight - anchor.axRect.maxY,
                width: anchor.axRect.width,
                height: anchor.axRect.height
            )
        } else {
            let mouse = NSEvent.mouseLocation
            caret = CGRect(x: mouse.x - 1, y: mouse.y, width: 2, height: 18)
        }

        if caret.height < 12 {
            caret.size.height = 18
        }
        let screen = NSScreen.screens.first {
            $0.frame.contains(CGPoint(x: caret.midX, y: caret.midY))
        } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let margin: CGFloat = 8
        let gap: CGFloat = 8

        var originX = caret.midX - windowSize.width / 2
        originX = min(
            max(originX, visible.minX + margin),
            visible.maxX - margin - windowSize.width
        )

        // The window includes the transparent glow inset. "Above the caret"
        // means the visible panel's bottom edge sits `gap` above the line.
        let inset = Theme.panelInset
        let above = caret.maxY + gap - inset
        let aboveContentTop = above + windowSize.height - inset
        let fitsAbove = aboveContentTop <= visible.maxY - margin && above >= visible.minY + margin

        var originY: CGFloat
        if fitsAbove {
            originY = above
        } else {
            let below = caret.minY - gap + inset - windowSize.height
            let belowContentBottom = below + inset
            let fitsBelow = belowContentBottom >= visible.minY + margin
            if fitsBelow {
                originY = below
            } else {
                originY = min(
                    max(above, visible.minY + margin),
                    visible.maxY - margin - windowSize.height
                )
            }
        }

        originY = min(
            max(originY, visible.minY + margin),
            visible.maxY - margin - windowSize.height
        )

        return CGRect(
            x: floor(originX),
            y: floor(originY),
            width: windowSize.width,
            height: windowSize.height
        )
    }
}
