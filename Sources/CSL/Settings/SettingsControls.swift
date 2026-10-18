import AppKit

// MARK: - Button

class PixelButton: NSButton {
    enum Style {
        case primary
        case ghost
        case danger
    }

    var style: Style = .ghost {
        didSet { needsDisplay = true }
    }

    private var hovering = false

    init(_ title: String, style: Style = .ghost, target: AnyObject? = nil, action: Selector? = nil) {
        super.init(frame: .zero)
        self.title = title
        self.style = style
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        font = Theme.display(9.5)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let size = (title as NSString).size(withAttributes: [.font: Theme.display(9.5)])
        return NSSize(width: ceil(size.width) + 24, height: 28)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)

        let background: NSColor
        let foreground: NSColor
        let border: NSColor

        switch style {
        case .primary:
            background = isHighlighted ? Theme.accentDim : Theme.accent
            foreground = Theme.bg
            border = background
        case .ghost:
            background = hovering ? Theme.bgSelected : .clear
            foreground = hovering ? Theme.text : Theme.textDim
            border = hovering ? Theme.borderBright : Theme.border
        case .danger:
            background = hovering ? Theme.danger.withAlphaComponent(0.12) : .clear
            foreground = Theme.danger
            border = Theme.danger.withAlphaComponent(0.55)
        }

        PixelDraw.fill(bounds, background)
        PixelDraw.frame(rect, thickness: 1, color: border, notch: 2)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(9.5),
            .foregroundColor: foreground,
            .paragraphStyle: paragraph
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            in: CGRect(x: 0, y: floor((bounds.height - size.height) / 2) - 1, width: bounds.width, height: size.height + 4),
            withAttributes: attributes
        )
    }
}

final class ClosureButton: PixelButton {
    private var onTap: (() -> Void)?

    init(_ title: String, style: Style = .ghost, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(title, style: style, target: nil, action: nil)
        target = self
        action = #selector(tapped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAction(_ closure: @escaping () -> Void) {
        onTap = closure
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - Text field

final class PixelField: NSView, NSTextFieldDelegate {
    let textField = PixelTextField(frame: .zero)
    var onSubmit: (() -> Void)?
    private var hasFocus = false

    var stringValue: String {
        get { textField.stringValue }
        set { textField.stringValue = newValue }
    }

    init(placeholder: String) {
        super.init(frame: .zero)

        textField.font = Theme.display(11.5)
        textField.textColor = Theme.text
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.delegate = self
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .font: Theme.display(9),
                .foregroundColor: Theme.textFaint
            ]
        )
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func focus() {
        window?.makeFirstResponder(textField)
        textField.styleEditor()
    }

    override func layout() {
        super.layout()
        textField.frame = CGRect(x: 8, y: 5, width: bounds.width - 16, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.fill(bounds, Theme.bg)
        PixelDraw.frame(
            bounds.insetBy(dx: 0.5, dy: 0.5),
            thickness: 1,
            color: hasFocus ? Theme.accentDim : Theme.border,
            notch: 2
        )
    }

    override func mouseDown(with event: NSEvent) {
        focus()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        hasFocus = true
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        hasFocus = false
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?()
            return true
        }
        return false
    }
}

// MARK: - Progress bar

final class PixelProgressBar: NSView {
    var fraction: Double = 0 {
        didSet { needsDisplay = true }
    }

    var tint: NSColor = Theme.accent {
        didSet { needsDisplay = true }
    }

    var indeterminate = false {
        didSet { needsDisplay = true }
    }

    var phase: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        PixelDraw.fill(bounds, Theme.bg)
        PixelDraw.frame(bounds.insetBy(dx: 0.5, dy: 0.5), thickness: 1, color: Theme.border, notch: 2)

        let inner = bounds.insetBy(dx: 4, dy: 4).integral
        let count = 48
        let gap: CGFloat = 2
        let available = inner.width - CGFloat(count - 1) * gap
        let blockWidth = floor(available / CGFloat(count))
        guard blockWidth >= 1 else { return }

        let totalWidth = blockWidth * CGFloat(count) + gap * CGFloat(count - 1)
        let startX = inner.minX + floor((inner.width - totalWidth) / 2)
        let filled = Int((fraction * Double(count)).rounded())
        let center = Int(phase * Double(count))

        for index in 0..<count {
            var isOn = index < filled
            if indeterminate {
                isOn = (index - center + count) % count < max(3, count / 7)
            }
            let rect = CGRect(
                x: startX + CGFloat(index) * (blockWidth + gap),
                y: inner.minY,
                width: blockWidth,
                height: inner.height
            )
            PixelDraw.fill(rect, isOn ? tint : Theme.line)
        }
    }
}

// MARK: - Lists

final class PixelListView: NSView {
    private(set) var rows: [NSView] = []
    var rowHeight: CGFloat = 52
    var emptyText: String = ""

    override var isFlipped: Bool { true }

    func setRows(_ newRows: [NSView], rowHeight: CGFloat) {
        for row in rows {
            row.removeFromSuperview()
        }
        rows = newRows
        self.rowHeight = rowHeight
        for row in newRows {
            addSubview(row)
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard !rows.isEmpty else { return }
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(
                x: 0,
                y: CGFloat(index) * rowHeight,
                width: bounds.width,
                height: rowHeight
            )
        }
        let height = max(1, CGFloat(rows.count) * rowHeight)
        if abs(frame.height - height) > 0.5 {
            frame.size.height = height
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard rows.isEmpty, !emptyText.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (emptyText as NSString).draw(
            in: CGRect(x: 0, y: max(12, (bounds.height - 16) / 2), width: bounds.width, height: 16),
            withAttributes: [
                .font: Theme.display(9),
                .foregroundColor: Theme.textFaint,
                .paragraphStyle: paragraph
            ]
        )
    }
}

final class ScrollListView: NSView {
    let scrollView = NSScrollView()
    let listView = PixelListView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView.documentView = listView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.contentView.drawsBackground = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func setRows(_ rows: [NSView], rowHeight: CGFloat, emptyText: String) {
        listView.emptyText = emptyText
        listView.setRows(rows, rowHeight: rowHeight)
        let height = rows.isEmpty
            ? max(1, scrollView.contentSize.height)
            : max(1, rowHeight * CGFloat(rows.count))
        listView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(1, scrollView.contentSize.width),
            height: height
        )
        scrollView.documentView = listView
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        listView.frame.size.width = scrollView.contentSize.width
        if listView.rows.isEmpty {
            listView.frame.size.height = max(1, scrollView.contentSize.height)
        }
    }
}

// MARK: - Row base

class SettingsRow: NSView {
    let rowHeight: CGFloat
    var onRemove: (() -> Void)?
    var onReindex: (() -> Void)?
    private var hovering = false

    init(height: CGFloat) {
        self.rowHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            PixelDraw.fill(bounds, Theme.bgSelected.withAlphaComponent(0.55))
        }
        PixelDraw.hLine(x: 0, y: bounds.maxY - 1, width: bounds.width, color: Theme.line)
    }
}
