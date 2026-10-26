import AppKit

final class PickerTextField: NSTextField {
    var onMouseDown: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        isBezeled = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
        font = Theme.display(20)
        textColor = Theme.text
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        cell?.isScrollable = true
        cell?.wraps = false
        cell?.usesSingleLineMode = true
        if let cell = cell as? NSTextFieldCell {
            cell.placeholderAttributedString = nil
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        styleEditor()
        return accepted
    }

    func styleEditor() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = Theme.accent
        editor.selectedTextAttributes = [
            .backgroundColor: Theme.accent,
            .foregroundColor: Theme.bg
        ]
        editor.drawsBackground = false
        editor.font = font
        var attributes = editor.typingAttributes
        attributes[.font] = font
        attributes[.foregroundColor] = Theme.text
        editor.typingAttributes = attributes
    }
}

/// Draws the empty-query placeholder centered in the field. The native
/// NSTextField placeholder is top-aligned in its cell, which looks off in the
/// taller pixel field.
final class SearchPlaceholderView: NSView {
    var text = "SEARCH EMOJI" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(15),
            .foregroundColor: Theme.textFaint
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(
            x: 4,
            y: (bounds.height - size.height) / 2,
            width: max(1, bounds.width - 4),
            height: size.height
        )
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
