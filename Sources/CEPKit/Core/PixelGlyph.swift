import AppKit

/// Hand-drawn 10×10 pixel glyphs for the menu bar and status rows.
/// Keeping these as bitmaps avoids blurry SF Symbols in the pixel UI.
enum PixelGlyph: String {
    case smiley
    case gear
    case power
    case sparkle
    case globe

    private var bitmap: [String] {
        switch self {
        case .smiley:
            return [
                "...####...",
                "..#....#..",
                ".#.#..#.#.",
                "#..#..#..#",
                "#........#",
                "#.#....#.#",
                "#..####..#",
                ".#......#.",
                "..#....#..",
                "...####..."
            ]
        case .gear:
            return [
                "....##....",
                "..######..",
                ".#.####.#.",
                "##.####.##",
                "##.####.##",
                "##.####.##",
                ".#.####.#.",
                "..######..",
                "....##....",
                ".........."
            ]
        case .power:
            return [
                "....##....",
                "...####...",
                "..#.##.#..",
                ".#..##..#.",
                ".#..##..#.",
                ".#..##..#.",
                ".#..##..#.",
                "..#.##.#..",
                "...####...",
                ".........."
            ]
        case .sparkle:
            return [
                "....##....",
                "....##....",
                "...####...",
                "..######..",
                "##########",
                "##########",
                "..######..",
                "...####...",
                "....##....",
                ".........."
            ]
        case .globe:
            return [
                "...####...",
                "..#.##.#..",
                ".#..##..#.",
                "#.######.#",
                "#...##...#",
                "#.######.#",
                ".#..##..#.",
                "..#.##.#..",
                "...####...",
                ".........."
            ]
        }
    }

    /// Renders the bitmap into a square NSImage. Cell size is an integer number
    /// of points, so the glyph stays crisp at every size.
    func image(size: CGFloat, color: NSColor) -> NSImage {
        let rows = bitmap.count
        let columns = bitmap.first?.count ?? 0
        let cell = max(1, floor(size / CGFloat(max(rows, columns))))

        return NSImage(
            size: NSSize(width: CGFloat(columns) * cell, height: CGFloat(rows) * cell),
            flipped: false
        ) { rect in
            color.setFill()
            let offsetX = floor((rect.width - CGFloat(columns) * cell) / 2)
            let offsetY = floor((rect.height - CGFloat(rows) * cell) / 2)

            for (rowIndex, row) in bitmap.enumerated() {
                let y = CGFloat(rows - 1 - rowIndex) * cell + offsetY
                for (columnIndex, character) in row.enumerated() where character == "#" {
                    let x = CGFloat(columnIndex) * cell + offsetX
                    CGRect(x: x, y: y, width: cell, height: cell).fill()
                }
            }
            return true
        }
    }
}
