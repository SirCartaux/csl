import AppKit

/// Thin pixel scrollbar for the character grid. The native scroller is hidden
/// so the panel keeps its hard-edged look; this overlay shows the same
/// information in three amber pixels.
final class ScrollIndicatorView: NSView {
    weak var scrollView: NSScrollView? {
        didSet { attach() }
    }

    private var observer: NSObjectProtocol?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func attach() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        guard let scrollView else { return }
        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    func update() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let scrollView,
              let document = scrollView.documentView else { return }
        let visible = scrollView.contentView.bounds.height
        let total = document.frame.height
        guard total > visible + 1, visible > 1 else { return }

        let track = CGRect(x: bounds.width - 3, y: 2, width: 1, height: bounds.height - 4)
        PixelDraw.fill(track, Theme.line.withAlphaComponent(0.55))

        let fraction = min(1, max(0, visible / total))
        let thumbHeight = max(14, floor((bounds.height - 4) * fraction))
        let scrollable = max(1, total - visible)
        let progress = min(1, max(0, scrollView.contentView.bounds.origin.y / scrollable))
        let thumbY = 2 + progress * (bounds.height - 4 - thumbHeight)
        PixelDraw.fill(
            CGRect(x: bounds.width - 4, y: thumbY, width: 3, height: thumbHeight),
            Theme.accentDim
        )
        PixelDraw.fill(
            CGRect(x: bounds.width - 4, y: thumbY, width: 1, height: thumbHeight),
            Theme.accent.withAlphaComponent(0.7)
        )
    }
}
