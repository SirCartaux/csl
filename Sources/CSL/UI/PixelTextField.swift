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
                .backgroundColor: inlineCommand.tint.withAlphaComponent(0.12),
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

    func inputCaretRect() -> CGRect {
        if let editor = currentEditor() as? NSTextView, let window {
            guard !editor.hasMarkedText() else { return .null }
            let end = (editor.string as NSString).length
            guard editor.selectedRange == NSRange(location: end, length: 0) else { return .null }
            let screen = editor.firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
            let rect = convert(window.convertFromScreen(screen), from: nil)
            return rect.maxX <= bounds.maxX && rect.minX >= bounds.minX ? rect : .null
        }
        let title = cell?.titleRect(forBounds: bounds) ?? bounds
        let x = title.minX + attributedStringValue.size().width
        return x < bounds.maxX ? CGRect(x: x, y: title.minY, width: 0, height: title.height) : .null
    }

    /// Use the field editor's glyph geometry when it is scrolled. The effect
    /// must follow the visible prefix rather than guessing from text length.
    func inlinePrefixRect() -> CGRect {
        guard let command = inlineCommand else { return .null }
        if let editor = currentEditor() as? NSTextView, let window {
            guard !editor.hasMarkedText(),
                  NSMaxRange(command.prefixRange) <= (editor.string as NSString).length else { return .null }
            // NSTextInputClient works with both TextKit generations. Reading
            // layoutManager would switch modern editors into compatibility mode
            // during a keystroke and can disrupt their pending undo operation.
            let screenRect = editor.firstRect(forCharacterRange: command.prefixRange, actualRange: nil)
            return convert(window.convertFromScreen(screenRect), from: nil).intersection(bounds)
        }
        let text = attributedStringValue
        guard NSMaxRange(command.prefixRange) <= text.length else { return .null }
        let leading = text.attributedSubstring(from: NSRange(location: 0, length: command.prefixRange.location)).size().width
        let size = text.attributedSubstring(from: command.prefixRange).size()
        let title = cell?.titleRect(forBounds: bounds) ?? bounds
        return CGRect(x: title.minX + leading, y: title.midY - size.height / 2,
                      width: size.width, height: size.height).intersection(bounds)
    }
}
