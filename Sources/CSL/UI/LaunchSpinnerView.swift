import AppKit
import QuartzCore

/// Small pixel chase shown on the row that is currently being launched.
final class LaunchSpinnerView: NSView {
    private var cells: [CALayer] = []
    private var running = false
    private let ring: [(Int, Int)] = [
        (0, 0), (1, 0), (2, 0), (2, 1),
        (2, 2), (1, 2), (0, 2), (0, 1)
    ]

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        buildCells()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        guard !cells.isEmpty else { return }
        let gap = max(1, Theme.ls(2))
        let cell = max(1, floor((bounds.width - 2 * gap) / 3))
        let content = cell * 3 + gap * 2
        let origin = floor((bounds.width - content) / 2)
        for (index, layer) in cells.enumerated() {
            let (column, row) = ring[index]
            layer.frame = CGRect(
                x: origin + CGFloat(column) * (cell + gap),
                y: origin + CGFloat(row) * (cell + gap),
                width: cell,
                height: cell
            )
        }
    }

    func start() {
        guard !running else { return }
        running = true
        isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        let now = CACurrentMediaTime()
        for (index, cell) in cells.enumerated() {
            cell.removeAllAnimations()
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0.18, 1.0, 0.18]
            pulse.keyTimes = [0.0, 0.30, 1.0]
            pulse.duration = 0.72
            pulse.beginTime = now + Double(index) * 0.075
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            cell.add(pulse, forKey: "launchPulse")
        }
    }

    func stop() {
        guard running else { return }
        running = false
        isHidden = true
        for cell in cells {
            cell.removeAllAnimations()
        }
    }

    private func buildCells() {
        for _ in 0..<8 {
            let cell = CALayer()
            cell.backgroundColor = Theme.success.cgColor
            cell.shadowColor = Theme.success.cgColor
            cell.shadowOffset = .zero
            cell.shadowRadius = Theme.ls(3)
            cell.shadowOpacity = 0.35
            cell.opacity = 0.18
            layer?.addSublayer(cell)
            cells.append(cell)
        }
    }
}
