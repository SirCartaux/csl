import AppKit
import QuartzCore

enum PixelRevealStyle: Equatable {
    /// Pixels appear in a radial wave from a point in the target layer.
    case radial(center: CGPoint)
    /// Pixels appear in a completely random order.
    case random
    /// Pixels appear column by column from left to right.
    case horizontal
}

/// A reusable grid of square CALayers used as a layer mask. The grid is built
/// once per size/scale and then only animated, so opening, closing and results
/// never allocate layers on the main thread during typing.
final class PixelRevealGrid {
    private struct Key: Equatable {
        var size: CGSize
        var cellSize: CGFloat
        var style: PixelRevealStyle
    }

    private var container: CALayer?
    private var cells: [CALayer] = []
    private var normalizedPosition: [CGFloat] = []
    private var key: Key?
    private var style: PixelRevealStyle = .random

    /// Build the grid ahead of time (during panel pre-warm).
    func prewarm(size: CGSize, cellSize: CGFloat, style: PixelRevealStyle) {
        buildIfNeeded(size: size, cellSize: cellSize, style: style)
    }

    /// Apply the mask and put every pixel in the hidden or visible state.
    func prepare(
        on target: CALayer,
        size: CGSize,
        cellSize: CGFloat,
        style: PixelRevealStyle,
        visible: Bool
    ) {
        buildIfNeeded(size: size, cellSize: cellSize, style: style)
        guard let container else { return }
        target.mask = container
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in cells {
            cell.removeAllAnimations()
            cell.transform = CATransform3DIdentity
            cell.opacity = visible ? 1 : 0
        }
        CATransaction.commit()
    }

    /// Fade every pixel in. Pixels keep their size; only opacity changes.
    /// Radial waves start at the search bar, random waves have no origin.
    @discardableResult
    func animateOpen(
        on target: CALayer,
        spread: TimeInterval = 0.12,
        jitter: TimeInterval = 0.05,
        duration: TimeInterval = 0.001
    ) -> TimeInterval {
        guard let container else { return 0 }
        target.mask = container
        let now = CACurrentMediaTime()
        var maxDelay: TimeInterval = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.transform = CATransform3DIdentity
            cell.opacity = 1

            let delay = revealDelay(index: index, opening: true, spread: spread, jitter: jitter)
            maxDelay = max(maxDelay, delay)

            // A discrete keyframe: no cross-fade, the pixel jumps 0 -> 1.
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 1.0]
            fade.keyTimes = [0.0, 1.0]
            fade.calculationMode = .discrete
            fade.beginTime = now + delay
            fade.duration = duration
            fade.fillMode = .both
            fade.isRemovedOnCompletion = true
            cell.add(fade, forKey: "pixelStep")
        }
        CATransaction.commit()
        return maxDelay + duration
    }

    /// Fade every pixel out. Radial close waves disappear from the outside in;
    /// random close waves have no origin.
    @discardableResult
    func animateClose(
        on target: CALayer,
        spread: TimeInterval = 0.12,
        jitter: TimeInterval = 0.05,
        duration: TimeInterval = 0.001
    ) -> TimeInterval {
        guard let container else { return 0 }
        target.mask = container
        let now = CACurrentMediaTime()
        var maxDelay: TimeInterval = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.transform = CATransform3DIdentity
            cell.opacity = 0

            let delay = revealDelay(index: index, opening: false, spread: spread, jitter: jitter)
            maxDelay = max(maxDelay, delay)

            // A discrete keyframe: no cross-fade, the pixel jumps 1 -> 0.
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1.0, 0.0]
            fade.keyTimes = [0.0, 1.0]
            fade.calculationMode = .discrete
            fade.beginTime = now + delay
            fade.duration = duration
            fade.fillMode = .both
            fade.isRemovedOnCompletion = true
            cell.add(fade, forKey: "pixelStep")
        }
        CATransaction.commit()
        return maxDelay + duration
    }

    private func revealDelay(
        index: Int,
        opening: Bool,
        spread: TimeInterval,
        jitter: TimeInterval
    ) -> TimeInterval {
        let random = Double.random(in: 0...1)
        switch style {
        case .random:
            return random * spread
        case .radial:
            let position = Double(normalizedPosition[index])
            let base = opening ? position * spread : (1 - position) * spread
            // Randomness grows the farther a pixel is from the origin.
            let weight = 0.25 + 0.75 * position
            return base + random * jitter * weight
        case .horizontal:
            let position = Double(normalizedPosition[index])
            let base = opening ? position * spread : (1 - position) * spread
            return base + random * jitter
        }
    }

    /// Remove the mask but keep the grid for the next animation.
    func clear(from target: CALayer) {
        target.mask = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in cells {
            cell.removeAllAnimations()
        }
        CATransaction.commit()
    }

    // MARK: - Grid

    private func buildIfNeeded(size: CGSize, cellSize: CGFloat, style: PixelRevealStyle) {
        let newKey = Key(size: size, cellSize: cellSize, style: style)
        if key == newKey, container != nil { return }

        let width = max(1, size.width)
        let height = max(1, size.height)
        let cell = max(1, cellSize)
        let columns = max(1, Int(ceil(width / cell)))
        let rows = max(1, Int(ceil(height / cell)))

        let container = CALayer()
        container.frame = CGRect(x: 0, y: 0, width: width, height: height)
        container.masksToBounds = false
        container.isGeometryFlipped = true

        var newCells: [CALayer] = []
        var positions: [CGFloat] = []
        newCells.reserveCapacity(columns * rows)
        positions.reserveCapacity(columns * rows)

        var maxDistance: CGFloat = 1
        if case let .radial(center) = style {
            for x in [CGFloat(0), width] {
                for y in [CGFloat(0), height] {
                    maxDistance = max(maxDistance, hypot(x - center.x, y - center.y))
                }
            }
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let x = CGFloat(column) * cell
                let y = CGFloat(row) * cell
                let w = min(cell, width - x)
                let h = min(cell, height - y)
                guard w > 0, h > 0 else { continue }

                let layer = CALayer()
                layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                layer.position = CGPoint(x: x + w / 2, y: y + h / 2)
                layer.backgroundColor = NSColor.white.cgColor
                container.addSublayer(layer)
                newCells.append(layer)

                switch style {
                case let .radial(center):
                    let distance = hypot(layer.position.x - center.x, layer.position.y - center.y)
                    positions.append(min(1, distance / maxDistance))
                case .horizontal:
                    positions.append(min(1, layer.position.x / width))
                case .random:
                    positions.append(0)
                }
            }
        }

        self.container = container
        self.cells = newCells
        self.normalizedPosition = positions
        self.key = newKey
        self.style = style
    }
}
