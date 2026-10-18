import AppKit
import ServiceManagement

// MARK: - Row helpers

private func drawRowText(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    font: CGFloat,
    color: NSColor,
    bold: Bool = false
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(
        in: CGRect(x: x, y: y, width: width, height: font + 7),
        withAttributes: [
            .font: bold ? Theme.displayBold(font) : Theme.display(font),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

// MARK: - Ignore rows

final class IgnoreFolderRow: SettingsRow {
    private let path: String
    private let name: String
    private let removeButton: ClosureButton

    init(path: String, onRemove: @escaping () -> Void) {
        self.path = path
        name = URL(fileURLWithPath: path).lastPathComponent
        removeButton = ClosureButton("X", style: .ghost, onTap: onRemove)
        super.init(height: 48)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        removeButton.frame = CGRect(x: bounds.width - 32, y: 12, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawRowText(name, x: 14, y: 6, width: bounds.width - 55, font: 12, color: Theme.text, bold: true)
        drawRowText(PathDisplay.pretty(path), x: 14, y: 24, width: bounds.width - 55, font: 8.5, color: Theme.textFaint)
    }
}

final class ExtensionRow: SettingsRow {
    private let ext: String
    private let removeButton: ClosureButton

    init(ext: String, onRemove: @escaping () -> Void) {
        self.ext = ext
        removeButton = ClosureButton("X", style: .ghost, onTap: onRemove)
        super.init(height: 34)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        removeButton.frame = CGRect(x: bounds.width - 32, y: 5, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawRowText(".\(ext.uppercased())", x: 14, y: 6, width: bounds.width - 55, font: 12, color: Theme.text)
    }
}

// MARK: - Ignore section

final class IgnoreSection: SettingsSection {
    private let folderList = ScrollListView()
    private let extensionList = ScrollListView()
    private let addFolderButton = ClosureButton("+ ORDNER", style: .ghost) {}
    private let extensionField = PixelField(placeholder: "Z.B. PSD, AEP, MOV")
    private let addExtensionButton = ClosureButton("+ HINZUFÜGEN", style: .primary) {}
    private var errorText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(folderList)
        addSubview(extensionList)
        addSubview(extensionField)
        addSubview(addFolderButton)
        addSubview(addExtensionButton)

        addFolderButton.setAction { [weak self] in self?.addFolder() }
        addExtensionButton.setAction { [weak self] in self?.addExtensions() }
        extensionField.onSubmit = { [weak self] in self?.addExtensions() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        addFolderButton.frame = CGRect(x: bounds.width - 100, y: 60, width: 100, height: 26)
        folderList.frame = CGRect(x: 0, y: 92, width: bounds.width, height: 150)

        extensionField.frame = CGRect(x: 0, y: 276, width: 300, height: 30)
        addExtensionButton.frame = CGRect(x: 308, y: 276, width: 140, height: 30)
        extensionList.frame = CGRect(x: 0, y: 326, width: bounds.width, height: max(40, bounds.height - 326))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(
            title: "IGNORIEREN",
            subtitle: "ORDNER UND DATEIFORMATE, DIE NIEMALS IN DER SUCHE AUFTAUCHEN SOLLEN."
        )
        drawText("IGNORIERTE ORDNER", x: 0, y: 66, width: 240, font: 8.5, color: Theme.textDim)
        drawText("DATEIFORMATE", x: 0, y: 256, width: 200, font: 8.5, color: Theme.textDim)
        drawText("KOMMAGETRENNT", x: 308, y: 256, width: 140, font: 7.5, color: Theme.textFaint)
        if let errorText {
            drawText(errorText, x: 0, y: 310, width: bounds.width, font: 8, color: Theme.danger)
        } else {
            drawText("WIRD AUS INDEX UND SUCHE AUSGEBLENDET.", x: 0, y: 310, width: bounds.width, font: 8, color: Theme.textFaint)
        }
    }

    override func reload() {
        let store = SettingsStore.shared
        folderList.setRows(
            store.settings.ignoredFolders.map { folder in
                IgnoreFolderRow(path: folder) {
                    store.removeIgnoredFolder(folder)
                }
            },
            rowHeight: 48,
            emptyText: "KEINE IGNORIERTEN ORDNER."
        )
        extensionList.setRows(
            store.settings.ignoredExtensions.map { ext in
                ExtensionRow(ext: ext) {
                    store.removeIgnoredExtension(ext)
                }
            },
            rowHeight: 34,
            emptyText: "KEINE IGNORIERTEN DATEIFORMATE."
        )
        needsDisplay = true
    }

    private func addFolder() {
        let urls = openPanel(
            prompt: "IGNORIEREN",
            message: "Ordner auswählen, die CSL nicht durchsuchen soll."
        )
        guard !urls.isEmpty else { return }
        for url in urls {
            let path = SettingsStore.normalizeFolder(url.path)
            let wasIndexed = SettingsStore.shared.settings.indexedFolders.contains(path)
            SettingsStore.shared.addIgnoredFolder(path)
            if wasIndexed {
                IndexCoordinator.shared.removeFolder(path)
            }
        }
        reload()
    }

    private func addExtensions() {
        let added = SettingsStore.shared.addIgnoredExtensions(extensionField.stringValue)
        if added.isEmpty {
            errorText = "KEINE GÜLTIGE, NEUE ENDUNG."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.errorText = nil
                self?.needsDisplay = true
            }
        } else {
            errorText = nil
            extensionField.stringValue = ""
        }
        needsDisplay = true
    }
}

// MARK: - Website row

final class WebsiteRowView: SettingsRow {
    private let site: WebsiteEntry
    private let removeButton: ClosureButton
    private let retryButton: ClosureButton

    init(site: WebsiteEntry, onRemove: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.site = site
        removeButton = ClosureButton("X", style: .ghost, onTap: onRemove)
        retryButton = ClosureButton("ICON", style: .ghost, onTap: onRetry)
        super.init(height: 56)
        addSubview(removeButton)
        addSubview(retryButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        removeButton.frame = CGRect(x: bounds.width - 32, y: 16, width: 24, height: 24)
        retryButton.frame = CGRect(x: bounds.width - 88, y: 16, width: 50, height: 24)
        retryButton.isHidden = !FaviconService.shared.didFail(site)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let iconBox = CGRect(x: 14, y: 13, width: 30, height: 30)
        if let image = FaviconService.shared.image(for: site) {
            image.draw(
                in: iconBox,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            PixelDraw.fill(iconBox, Theme.bgRaised)
            PixelDraw.frame(iconBox, thickness: 1, color: Theme.border, notch: 2)
            PixelGlyph.globe.image(size: 18, color: Theme.textDim).draw(
                in: CGRect(x: iconBox.minX + 6, y: iconBox.minY + 6, width: 18, height: 18)
            )
        }

        drawRowText(site.displayTitle, x: 54, y: 7, width: bounds.width - 150, font: 12.5, color: Theme.text, bold: true)
        let subtitle = site.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "WEBSITE" : site.host
        drawRowText(subtitle, x: 54, y: 26, width: bounds.width - 150, font: 8.5, color: Theme.textFaint)

        let meta: String?
        if FaviconService.shared.iconURL(for: site) != nil {
            meta = nil
        } else if FaviconService.shared.didFail(site) {
            meta = "KEIN ICON GEFUNDEN"
        } else {
            meta = "ICON WIRD GELADEN..."
        }
        if let meta {
            drawRowText(
                meta,
                x: 54,
                y: 40,
                width: bounds.width - 150,
                font: 7.5,
                color: FaviconService.shared.didFail(site) ? Theme.textFaint : Theme.accentDim
            )
        }

    }
}

// MARK: - Websites section

final class WebsitesSection: SettingsSection {
    private let urlField = PixelField(placeholder: "HTTPS://URL")
    private let nameField = PixelField(placeholder: "NAME (OPTIONAL)")
    private let addButton = ClosureButton("+", style: .primary) {}
    private let list = ScrollListView()
    private var errorText: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(urlField)
        addSubview(nameField)
        addSubview(addButton)
        addSubview(list)

        addButton.setAction { [weak self] in self?.addWebsite() }
        urlField.onSubmit = { [weak self] in self?.addWebsite() }
        nameField.onSubmit = { [weak self] in self?.addWebsite() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        urlField.frame = CGRect(x: 0, y: 66, width: 292, height: 30)
        nameField.frame = CGRect(x: 300, y: 66, width: 144, height: 30)
        addButton.frame = CGRect(x: 452, y: 66, width: 80, height: 30)
        list.frame = CGRect(x: 0, y: 126, width: bounds.width, height: max(40, bounds.height - 126))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(
            title: "WEBSITES",
            subtitle: "DEINE SEITEN ALS SUCHTREFFER. DAS ICON WIRD EINMAL IM HINTERGRUND GELADEN."
        )
        if let errorText {
            drawText(errorText, x: 0, y: 102, width: bounds.width, font: 8, color: Theme.danger)
        } else {
            drawText("ENTER FÜGT HINZU. URL OHNE HTTPS WIRD AUFGEFÜLLT.", x: 0, y: 102, width: bounds.width, font: 8, color: Theme.textFaint)
        }
    }

    override func reload() {
        let websites = SettingsStore.shared.settings.websites
        list.setRows(
            websites.map { site in
                WebsiteRowView(
                    site: site,
                    onRemove: {
                        SettingsStore.shared.removeWebsite(id: site.id)
                    },
                    onRetry: {
                        FaviconService.shared.retryIcon(for: site)
                    }
                )
            },
            rowHeight: 56,
            emptyText: "NOCH KEINE WEBSITES. FÜGE Z.B. NEWS.YCOMBINATOR.COM HINZU."
        )
        needsDisplay = true
    }

    func focusURLField() {
        urlField.focus()
    }

    private func addWebsite() {
        let raw = urlField.stringValue
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("BITTE EINE URL EINGEBEN.")
            return
        }
        guard SettingsStore.shared.addWebsite(rawURL: raw, title: nameField.stringValue) != nil else {
            showError("URL UNGÜLTIG ODER BEREITS VORHANDEN.")
            return
        }

        urlField.stringValue = ""
        nameField.stringValue = ""
        errorText = nil
        urlField.focus()
        reload()
    }

    private func showError(_ message: String) {
        errorText = message
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.errorText = nil
            self?.needsDisplay = true
        }
    }
}

// MARK: - General section

final class GeneralSection: SettingsSection {
    private let keyboardButton = ClosureButton("TASTENKURZBEFEHLE ÖFFNEN", style: .ghost) {}
    private let loginButton = ClosureButton("AUS", style: .ghost) {}
    private let dataButton = ClosureButton("IM FINDER ZEIGEN", style: .ghost) {}
    private let resetRankingButton = ClosureButton("LERNSTATISTIK ZURÜCKSETZEN", style: .ghost) {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(keyboardButton)
        addSubview(loginButton)
        addSubview(dataButton)
        addSubview(resetRankingButton)

        keyboardButton.setAction {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        loginButton.setAction { [weak self] in self?.toggleLogin() }
        dataButton.setAction {
            NSWorkspace.shared.open(AppPaths.baseDirectory)
        }
        resetRankingButton.setAction { [weak self] in
            ResultRanker.shared.reset()
            self?.resetRankingButton.title = "ZURÜCKGESETZT"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self?.resetRankingButton.title = "LERNSTATISTIK ZURÜCKSETZEN"
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        keyboardButton.frame = CGRect(x: 0, y: 172, width: 240, height: 28)
        loginButton.frame = CGRect(x: 0, y: 252, width: 80, height: 28)
        dataButton.frame = CGRect(x: 0, y: 340, width: 170, height: 28)
        resetRankingButton.frame = CGRect(x: 0, y: 364, width: 260, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(title: "ALLGEMEIN", subtitle: "HOTKEYS, LOGIN UND EIN BLICK AUF DIE DATEN.")

        drawText("HOTKEYS", x: 0, y: 64, width: 200, font: 8.5, color: Theme.textDim)
        var cursor = drawKeyCap("CMD+SPACE", x: 0, y: 84)
        cursor = drawKeyCap("OPT+SPACE", x: cursor + 8, y: 84)
        drawText("PANEL ÖFFNEN / SCHLIESSEN", x: cursor + 10, y: 86, width: 220, font: 8, color: Theme.textFaint)

        drawText("SPOTLIGHT", x: 0, y: 124, width: 200, font: 8.5, color: Theme.textDim)
        drawText(
            "SOLANGE SPOTLIGHT CMD+SPACE BELEGT, NUTZE OPT+SPACE ODER DEAKTIVIERE DEN SHORTCUT.",
            x: 0,
            y: 144,
            width: bounds.width,
            font: 8,
            color: Theme.textFaint
        )

        drawText("START", x: 0, y: 218, width: 200, font: 8.5, color: Theme.textDim)
        drawText("CSL BEIM ANMELDEN AUTOMATISCH STARTEN.", x: 92, y: 257, width: bounds.width - 92, font: 8, color: Theme.textFaint)

        drawText("DATEN", x: 0, y: 304, width: 200, font: 8.5, color: Theme.textDim)
        let stats = "\(CSLFormat.count(FileIndex.shared.totalCount)) EINTRÄGE / \(SettingsStore.shared.settings.indexedFolders.count) ORDNER / \(SettingsStore.shared.settings.websites.count) WEBSITES"
        drawText(stats, x: 0, y: 322, width: bounds.width, font: 8, color: Theme.textFaint)
        drawText(PathDisplay.pretty(AppPaths.baseDirectory.path), x: 180, y: 346, width: bounds.width - 180, font: 8, color: Theme.textFaint)
        drawText(
            "LERNT AUS ÖFFNEN / REVEAL / DRAG.",
            x: 270,
            y: 371,
            width: bounds.width - 270,
            font: 8,
            color: Theme.textFaint
        )

        drawText("ÜBER", x: 0, y: 394, width: 200, font: 8.5, color: Theme.textDim)
        drawText("CSL 0.4.2 - COMMAND SEARCH LAUNCHER", x: 0, y: 414, width: bounds.width, font: 8, color: Theme.textFaint)
        drawText("SWIFT + APPKIT / SILKSCREEN (OFL) / LOKAL, KEINE TELEMETRIE", x: 0, y: 430, width: bounds.width, font: 8, color: Theme.textFaint)
    }

    override func reload() {
        loginButton.title = launchAtLogin ? "AN" : "AUS"
        loginButton.style = launchAtLogin ? .primary : .ghost
        loginButton.needsDisplay = true
        needsDisplay = true
    }

    private var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func toggleLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.debug("login item failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "LAUNCH AT LOGIN"
            alert.informativeText = "macOS konnte CSL nicht als Login-Objekt eintragen. Lege CSL.app in /Applications ab und versuche es erneut."
            alert.alertStyle = .warning
            alert.runModal()
        }
        reload()
    }
}
