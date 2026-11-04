import AppKit

// MARK: - Shortcut row

final class ShortcutRowView: SettingsRow {
    private let shortcut: SearchShortcut
    private let removeButton: ClosureButton

    init(shortcut: SearchShortcut, onRemove: @escaping () -> Void) {
        self.shortcut = shortcut
        removeButton = ClosureButton("X", style: .ghost, onTap: onRemove)
        super.init(height: 58)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        removeButton.frame = CGRect(x: bounds.width - 32, y: 17, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconBox = CGRect(x: 12, y: 14, width: 30, height: 30)
        if let iconURL = ShortcutIconService.shared.iconURL(for: shortcut),
           let image = NSImage(contentsOf: iconURL) {
            image.draw(
                in: iconBox,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            PixelGlyph.globe.image(size: 18, color: Theme.textFaint).draw(
                in: CGRect(x: iconBox.minX + 6, y: iconBox.minY + 6, width: 18, height: 18)
            )
        }
        PixelDraw.frame(
            iconBox.insetBy(dx: -2, dy: -2),
            thickness: 1,
            color: shortcut.tint.withAlphaComponent(0.65),
            notch: 2
        )

        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(9),
            .foregroundColor: shortcut.tint
        ]
        let badgeText = shortcut.prefix as NSString
        let badgeSize = badgeText.size(withAttributes: badgeAttributes)
        let badgeRect = CGRect(
            x: 54,
            y: 20,
            width: max(28, badgeSize.width + 12),
            height: 18
        )
        PixelDraw.fill(badgeRect, shortcut.tint.withAlphaComponent(0.13))
        PixelDraw.frame(
            badgeRect.insetBy(dx: 0.5, dy: 0.5),
            thickness: 1,
            color: shortcut.tint,
            notch: 2
        )
        let badgeParagraph = NSMutableParagraphStyle()
        badgeParagraph.alignment = .center
        badgeText.draw(
            in: CGRect(x: badgeRect.minX + 3, y: badgeRect.minY + 4, width: badgeRect.width - 6, height: 12),
            withAttributes: [
                .font: Theme.displayBold(9),
                .foregroundColor: shortcut.tint,
                .paragraphStyle: badgeParagraph
            ]
        )

        let textX = badgeRect.maxX + 10
        (shortcut.name.uppercased() as NSString).draw(
            in: CGRect(x: textX, y: 7, width: bounds.width - textX - 42, height: 16),
            withAttributes: [
                .font: Theme.displayBold(11),
                .foregroundColor: Theme.text
            ]
        )
        (shortcut.host as NSString).draw(
            in: CGRect(x: textX, y: 26, width: bounds.width - textX - 42, height: 12),
            withAttributes: [
                .font: Theme.display(8),
                .foregroundColor: Theme.textFaint
            ]
        )
        (shortcut.searchTemplate as NSString).draw(
            in: CGRect(x: 54, y: 41, width: bounds.width - 96, height: 10),
            withAttributes: [
                .font: Theme.display(7),
                .foregroundColor: Theme.textFaint.withAlphaComponent(0.62)
            ]
        )
    }
}

// MARK: - Shortcut section

final class ShortcutSection: SettingsSection {
    private let prefixField = PixelField(placeholder: "KÜRZEL (G, GB)")
    private let nameField = PixelField(placeholder: "NAME (GOOGLE)")
    private let templateField = PixelField(placeholder: "SUCH-URL MIT {QUERY}")
    private let addButton = ClosureButton("+ HINZUFÜGEN", style: .primary) {}
    private let list = ScrollListView()
    private var errorText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(prefixField)
        addSubview(nameField)
        addSubview(templateField)
        addSubview(addButton)
        addSubview(list)

        addButton.setAction { [weak self] in self?.addShortcut() }
        for field in [prefixField, nameField, templateField] {
            field.onSubmit = { [weak self] in self?.addShortcut() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        prefixField.frame = CGRect(x: 0, y: 62, width: 72, height: 30)
        nameField.frame = CGRect(x: 80, y: 62, width: 190, height: 30)
        addButton.frame = CGRect(x: bounds.width - 146, y: 62, width: 146, height: 30)
        templateField.frame = CGRect(x: 0, y: 100, width: bounds.width, height: 30)
        list.frame = CGRect(x: 0, y: 154, width: bounds.width, height: max(40, bounds.height - 154))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(
            title: "KÜRZEL",
            subtitle: "WEBSITE-SUCHE DIREKT AUS DEM LAUNCHER: KÜRZEL, LEERZEICHEN, SUCHBEGRIFF."
        )
        drawText("SUCH-URL MIT PLACEHOLDER {QUERY}", x: 0, y: 136, width: 280, font: 7.5, color: Theme.textFaint)
        if let errorText {
            drawText(errorText, x: 0, y: 136, width: bounds.width, font: 8, color: Theme.danger, align: .right)
        }
    }

    override func reload() {
        list.setRows(
            ShortcutStore.shared.shortcuts
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { shortcut in
                ShortcutRowView(shortcut: shortcut) {
                    ShortcutStore.shared.remove(id: shortcut.id)
                }
            },
            rowHeight: 58,
            emptyText: "NOCH KEINE KÜRZEL. FÜGE Z.B. G FÜR GOOGLE HINZU."
        )
        needsDisplay = true
    }

    private func addShortcut() {
        errorText = nil
        let result = ShortcutStore.shared.add(
            prefix: prefixField.stringValue,
            name: nameField.stringValue,
            template: templateField.stringValue
        )
        switch result {
        case .success(let shortcut):
            ShortcutIconService.shared.fetchIcon(for: shortcut)
            prefixField.stringValue = ""
            nameField.stringValue = ""
            templateField.stringValue = ""
            reload()
            prefixField.focus()
        case .failure(let error):
            errorText = error.localizedDescription.uppercased()
            needsDisplay = true
        }
    }
}
