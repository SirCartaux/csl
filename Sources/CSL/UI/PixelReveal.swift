import AppKit
import QuartzCore

enum PixelRevealStyle: Equatable {
    /// Pixels disappear in a radial wave from a point in the cover.
    case radial(center: CGPoint)
    /// Pixels disappear in a completely random order.
    case random
}

/// A reusable grid of dark squares used as an opaque cover. Revealing the UI
/// removes cover pixels; closing covers them again. Unlike a layer mask this
/// never exposes the desktop through the window, so no white holes or seams
/// can flash during the animation.
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

    /// Add the cover above the target layer. `covered == true` starts with the
    /// UI hidden; `covered == false` starts with the UI visible.
    func prepare(
        on target: CALayer,
        frame: CGRect,
        cellSize: CGFloat,
        style: PixelRevealStyle,
        covered: Bool
    ) {
        buildIfNeeded(size: frame.size, cellSize: cellSize, style: style)
        guard let container else { return }
        container.removeFromSuperlayer()
        container.frame = frame
        target.addSublayer(container)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in cells {
            cell.removeAllAnimations()
            cell.opacity = covered ? 1 : 0
        }
        CATransaction.commit()
    }

    /// Remove cover pixels and reveal the content underneath.
    @discardableResult
    func animateReveal(
        spread: TimeInterval = 0.12,
        jitter: TimeInterval = 0.05,
        duration: TimeInterval = 0.001
    ) -> TimeInterval {
        guard let container else { return 0 }
        container.removeAllAnimations()
        let now = CACurrentMediaTime()
        var maxDelay: TimeInterval = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.opacity = 0
            let delay = stepDelay(index: index, covering: false, spread: spread, jitter: jitter)
            maxDelay = max(maxDelay, delay)
            let animation = stepAnimation(from: 1.0, to: 0.0, beginTime: now + delay, duration: duration)
            cell.add(animation, forKey: "pixelStep")
        }
        CATransaction.commit()
        return maxDelay + duration
    }

    /// Cover the content again, pixel by pixel.
    @discardableResult
    func animateCover(
        spread: TimeInterval = 0.12,
        jitter: TimeInterval = 0.05,
        duration: TimeInterval = 0.001
    ) -> TimeInterval {
        guard let container else { return 0 }
        container.removeAllAnimations()
        let now = CACurrentMediaTime()
        var maxDelay: TimeInterval = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, cell) in cells.enumerated() {
            cell.opacity = 1
            let delay = stepDelay(index: index, covering: true, spread: spread, jitter: jitter)
            maxDelay = max(maxDelay, delay)
            let animation = stepAnimation(from: 0.0, to: 1.0, beginTime: now + delay, duration: duration)
            cell.add(animation, forKey: "pixelStep")
        }
        CATransaction.commit()
        return maxDelay + duration
    }

    /// Remove the cover but keep the grid for the next animation.
    func clear() {
        container?.removeFromSuperlayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for cell in cells {
            cell.removeAllAnimations()
        }
        CATransaction.commit()
    }

    // MARK: - Animation

    private func stepAnimation(
        from: Double,
        to: Double,
        beginTime: CFTimeInterval,
        duration: TimeInterval
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [from, to]
        animation.keyTimes = [0.0, 1.0]
        animation.calculationMode = .discrete
        animation.beginTime = beginTime
        animation.duration = duration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = true
        return animation
    }

    private func stepDelay(
        index: Int,
        covering: Bool,
        spread: TimeInterval,
        jitter: TimeInterval
    ) -> TimeInterval {
        let random = Double.random(in: 0...1)
        switch style {
        case .random:
            return random * spread
        case .radial:
            let position = Double(normalizedPosition[index])
            // Reveal: near the search bar first. Cover: far pixels first.
            let base = covering ? (1 - position) * spread : position * spread
            let weight = 0.25 + 0.75 * position
            return base + random * jitter * weight
        }
    }

    // MARK: - Grid

    private func buildIfNeeded(size: CGSize, cellSize: CGFloat, style: PixelRevealStyle) {
        let newKey = Key(size: size, cellSize: cellSize, style: style)
        if key == newKey, container != nil { return }

        let width = max(1, size.width)
        let height = max(1, size.height)
        let cell = max(1, ceil(cellSize))
        let overlap: CGFloat = 1
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
                let w = min(cell + overlap, width - x)
                let h = min(cell + overlap, height - y)
                guard w > 0, h > 0 else { continue }

                let layer = CALayer()
                layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                layer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                layer.position = CGPoint(x: x + w / 2, y: y + h / 2)
                layer.backgroundColor = Theme.bg.cgColor
                container.addSublayer(layer)
                newCells.append(layer)

                switch style {
                case let .radial(center):
                    let distance = hypot(layer.position.x - center.x, layer.position.y - center.y)
                    positions.append(min(1, distance / maxDistance))
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
