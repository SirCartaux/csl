import AppKit

/// Hard-edged drawing helpers shared with CSL. Everything snaps to whole
/// points so the UI keeps its pixel look on Retina displays (1 pt == 2 px).
enum PixelDraw {
    static func fill(_ rect: CGRect, _ color: NSColor) {
        color.setFill()
        rect.integral.fill()
    }

    /// A rectangular frame with cut-out corners: the signature 8-bit border.
    static func frame(_ rect: CGRect, thickness: CGFloat = 1, color: NSColor, notch: CGFloat = 3) {
        let r = rect.integral
        let t = thickness
        let n = notch
        guard r.width > 2 * n, r.height > 2 * n else {
            fill(r, color)
            return
        }

        color.setFill()
        CGRect(x: r.minX + n, y: r.maxY - t, width: r.width - 2 * n, height: t).fill()
        CGRect(x: r.minX + n, y: r.minY, width: r.width - 2 * n, height: t).fill()
        CGRect(x: r.minX, y: r.minY + n, width: t, height: r.height - 2 * n).fill()
        CGRect(x: r.maxX - t, y: r.minY + n, width: t, height: r.height - 2 * n).fill()
        for corner in [
            CGPoint(x: r.minX + 1, y: r.maxY - 1),
            CGPoint(x: r.maxX - 1, y: r.maxY - 1),
            CGPoint(x: r.minX + 1, y: r.minY),
            CGPoint(x: r.maxX - 1, y: r.minY)
        ] {
            CGRect(x: corner.x, y: corner.y, width: 1, height: 1).fill()
        }
    }

    static func hLine(x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor, thickness: CGFloat = 1) {
        fill(CGRect(x: x, y: y, width: width, height: thickness), color)
    }

    static func vLine(x: CGFloat, y: CGFloat, height: CGFloat, color: NSColor, thickness: CGFloat = 1) {
        fill(CGRect(x: x, y: y, width: thickness, height: height), color)
    }

    static func dottedLine(x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor, step: CGFloat = 4) {
        color.setFill()
        var cursor = x
        while cursor < x + width {
            CGRect(x: cursor, y: y, width: 2, height: 1).fill()
            cursor += step
        }
    }

    /// 5×5 pixel chevron used as the "selected" marker and search prompt.
    static func chevron(x: CGFloat, y: CGFloat, unit: CGFloat, color: NSColor) {
        let pattern = [
            "##...",
            ".##..",
            "..##.",
            ".##..",
            "##..."
        ]
        color.setFill()
        for (row, line) in pattern.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                CGRect(
                    x: x + CGFloat(column) * unit,
                    y: y + CGFloat(4 - row) * unit,
                    width: unit,
                    height: unit
                ).fill()
            }
        }
    }

    /// A tiny 5×5 star, used for favorites in the grid.
    static func star(x: CGFloat, y: CGFloat, unit: CGFloat, color: NSColor) {
        let pattern = [
            "..#..",
            "..#..",
            "#####",
            ".###.",
            "..#.."
        ]
        color.setFill()
        for (row, line) in pattern.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                CGRect(
                    x: x + CGFloat(column) * unit,
                    y: y + CGFloat(4 - row) * unit,
                    width: unit,
                    height: unit
                ).fill()
            }
        }
    }
}
