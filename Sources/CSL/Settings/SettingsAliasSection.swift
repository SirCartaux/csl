import AppKit

// MARK: - Alias row

final class AliasRowView: SettingsRow {
    private let alias: SearchAlias
    private let removeButton: ClosureButton

    init(alias: SearchAlias, onRemove: @escaping () -> Void) {
        self.alias = alias
        removeButton = ClosureButton("X", style: .ghost, onTap: onRemove)
        super.init(height: 56)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        removeButton.frame = CGRect(x: bounds.width - 32, y: 16, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let icon = NSWorkspace.shared.icon(forFile: alias.targetPath)
        icon.draw(
            in: CGRect(x: 12, y: 12, width: 28, height: 28),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none]
        )

        let aliasAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.displayBold(12),
            .foregroundColor: alias.targetExists ? Theme.text : Theme.danger
        ]
        (alias.alias.uppercased() as NSString).draw(
            in: CGRect(x: 52, y: 6, width: bounds.width - 100, height: 17),
            withAttributes: aliasAttributes
        )

        let target = alias.targetName + (alias.isApplication ? "  ·  APP" : "  ·  DATEI")
        let targetAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8.5),
            .foregroundColor: Theme.textFaint
        ]
        (target as NSString).draw(
            in: CGRect(x: 52, y: 25, width: bounds.width - 100, height: 12),
            withAttributes: targetAttributes
        )
        (PathDisplay.pretty(alias.targetPath) as NSString).draw(
            in: CGRect(x: 52, y: 39, width: bounds.width - 100, height: 11),
            withAttributes: [
                .font: Theme.display(7),
                .foregroundColor: Theme.textFaint.withAlphaComponent(0.75)
            ]
        )
    }
}

// MARK: - Alias section

final class AliasSection: SettingsSection {
    private let list = ScrollListView()
    private let addButton = ClosureButton("+ ALIAS HINZUFÜGEN", style: .primary) {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(list)
        addSubview(addButton)
        addButton.setAction { [weak self] in self?.addAlias() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        addButton.frame = CGRect(x: bounds.width - 186, y: 0, width: 186, height: 28)
        list.frame = CGRect(x: 0, y: 70, width: bounds.width, height: max(40, bounds.height - 70))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(
            title: "ALIASSE",
            subtitle: "EIGENE SUCHWÖRTER FÜR APPS UND DATEIEN. RECHTSKLICK AUF EIN ERGEBNIS LEGT SCHNELL EINEN AN."
        )
        drawText(
            "TIPPST DU EINEN ALIAS, ERSCHEINT DAS ZIEL DIREKT IN DER SUCHE.",
            x: 0,
            y: 58,
            width: bounds.width - 200,
            font: 8,
            color: Theme.textFaint
        )
    }

    override func reload() {
        let aliases = AliasStore.shared.aliases
        list.setRows(
            aliases.map { alias in
                AliasRowView(alias: alias) {
                    AliasStore.shared.remove(id: alias.id)
                }
            },
            rowHeight: 56,
            emptyText: "NOCH KEINE ALIASSE. FÜGE EINEN ALIAS FÜR EINE APP ODER DATEI HINZU."
        )
        needsDisplay = true
    }

    private func addAlias() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "WEITER"
        panel.message = "App oder Datei auswählen, die über einen Alias gefunden werden soll."
        let response = panel.runModal()
        window?.makeKey()
        guard response == .OK, let url = panel.url else { return }
        _ = AliasPrompt.addAlias(for: url, title: AliasStore.displayName(for: url))
        reload()
    }
}
