import AppKit

final class PixelTextField: NSTextField {
    var onMouseDown: (() -> Void)?
    var inlineCommand: InlineCommand? { didSet { applyInlineStyle() } }
    private var hasInlineStyle = false

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
        applyInlineStyle()
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
        applyInlineStyle()
    }

    /// Attribute-only changes preserve text, selection, undo, caret and native
    /// horizontal scrolling. The prefix is still normal editable/copyable text.
    func applyInlineStyle() {
        // Ordinary queries retain the existing native editing path and allocate
        // no attributed copy. Only entering/leaving a command needs styling.
        guard inlineCommand != nil || hasInlineStyle else { return }
        let editor = currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
        let base: [NSAttributedString.Key: Any] = [
            .font: font ?? Theme.launcherDisplay(20), .foregroundColor: Theme.text
        ]
        var prefixAttributes: [NSAttributedString.Key: Any] = [:]
        if let inlineCommand {
            prefixAttributes = [
                .font: Theme.launcherDisplayBold(20),
                .foregroundColor: inlineCommand.tint,
                .backgroundColor: inlineCommand.tint.withAlphaComponent(0.19),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: inlineCommand.tint
            ]
        }
        if let editor, let storage = editor.textStorage {
            storage.beginEditing()
            storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
            if let inlineCommand, NSMaxRange(inlineCommand.prefixRange) <= storage.length {
                storage.addAttributes(prefixAttributes, range: inlineCommand.prefixRange)
            }
            storage.endEditing()
            // A space after the command must never inherit the command colour.
            editor.typingAttributes = base
        } else {
            let styled = NSMutableAttributedString(string: stringValue, attributes: base)
            if let inlineCommand, NSMaxRange(inlineCommand.prefixRange) <= styled.length {
                styled.addAttributes(prefixAttributes, range: inlineCommand.prefixRange)
            }
            attributedStringValue = styled
        }
        hasInlineStyle = inlineCommand != nil
    }
}
