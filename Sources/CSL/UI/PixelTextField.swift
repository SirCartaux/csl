import AppKit

final class PixelTextField: NSTextField {
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
            cell.placeholderAttributedString = NSAttributedString(
                string: "TYPE TO SEARCH",
                attributes: [
                    .font: Theme.display(15),
                    .foregroundColor: Theme.textFaint
                ]
            )
        }
    }

    /// The launcher field grows with the window; the Settings fields keep
    /// their fixed font.
    func applyLauncherScale() {
        font = Theme.launcherDisplay(20)
        if let editor = currentEditor() as? NSTextView {
            editor.font = font
            var attributes = editor.typingAttributes
            attributes[.font] = font
            editor.typingAttributes = attributes
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
    }
}
