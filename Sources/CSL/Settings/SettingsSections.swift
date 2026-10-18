import AppKit

// MARK: - Formatting

enum CSLFormat {
    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM. HH:mm"
        return formatter
    }()

    static func count(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func eta(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "-" }
        if seconds < 1 { return "<1 S" }
        if seconds < 60 { return "~\(Int(seconds.rounded())) S" }
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 {
            let rest = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "~\(totalMinutes) MIN \(rest) S"
        }
        return "~\(totalMinutes / 60) STD \(totalMinutes % 60) MIN"
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "-" }
        return dateFormatter.string(from: date)
    }
}

// MARK: - Base

class SettingsSection: NSView {
    override var isFlipped: Bool { true }

    func reload() {}
    func updateIndexProgress(_ progress: FolderIndexer.Progress?) {}

    func formatCount(_ value: Int) -> String { CSLFormat.count(value) }
    func formatETA(_ seconds: TimeInterval?) -> String { CSLFormat.eta(seconds) }
    func formatDate(_ date: Date?) -> String { CSLFormat.date(date) }

    func drawText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: CGFloat,
        color: NSColor,
        bold: Bool = false,
        align: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bold ? Theme.displayBold(font) : Theme.display(font),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(
            in: CGRect(x: x, y: y, width: width, height: font + 7),
            withAttributes: attributes
        )
    }

    func drawHeader(title: String, subtitle: String) {
        drawText(title, x: 0, y: 0, width: bounds.width - 180, font: 16, color: Theme.text, bold: true)
        drawText(subtitle, x: 0, y: 26, width: bounds.width, font: 8.5, color: Theme.textFaint)
    }

    @discardableResult
    func drawKeyCap(_ text: String, x: CGFloat, y: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.display(8),
            .foregroundColor: Theme.textDim
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: x, y: y, width: size.width + 10, height: 16).integral
        PixelDraw.frame(rect, thickness: 1, color: Theme.border, notch: 2)
        (text as NSString).draw(
            in: CGRect(x: rect.minX + 5, y: rect.minY + 3, width: size.width + 2, height: 10),
            withAttributes: attributes
        )
        return rect.maxX
    }

    func drawButtonBackground(_ rect: CGRect, color: NSColor, border: NSColor) {
        PixelDraw.fill(rect, color)
        PixelDraw.frame(rect.insetBy(dx: 0.5, dy: 0.5), thickness: 1, color: border, notch: 2)
    }

    func openPanel(prompt: String, message: String) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = prompt
        panel.message = message
        let response = panel.runModal()
        window?.makeKey()
        return response == .OK ? panel.urls : []
    }
}

// MARK: - Progress card

final class IndexProgressCard: NSView {
    private let bar = PixelProgressBar()
    private let cancel = ClosureButton("ABBRECHEN") {
        IndexCoordinator.shared.cancelAll()
    }

    private var progress: FolderIndexer.Progress?
    private var isIndexing = false
    private var totalEntries = 0
    private var lastIndexed: Date?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(bar)
        addSubview(cancel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(
        progress: FolderIndexer.Progress?,
        isIndexing: Bool,
        totalEntries: Int,
        lastIndexed: Date?
    ) {
        self.progress = progress
        self.isIndexing = isIndexing
        self.totalEntries = totalEntries
        self.lastIndexed = lastIndexed
        refresh()
    }

    func setProgress(_ progress: FolderIndexer.Progress?) {
        self.progress = progress
        self.isIndexing = progress != nil
        refresh()
    }

    private func refresh() {
        if let progress, isIndexing {
            bar.isHidden = false
            cancel.isHidden = false
            switch progress.phase {
            case .scanning:
                bar.indeterminate = true
                bar.phase += 0.05
            case .indexing, .saving:
                bar.indeterminate = false
                bar.fraction = progress.fraction
            }
        } else if isIndexing {
            bar.isHidden = false
            cancel.isHidden = false
            bar.indeterminate = true
        } else {
            bar.isHidden = true
            cancel.isHidden = true
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        bar.frame = CGRect(x: 14, y: 34, width: bounds.width - 28, height: 14)
        cancel.frame = CGRect(x: bounds.width - 102, y: 66, width: 88, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawButtonBackground(bounds, color: Theme.bgRaised, border: Theme.border)

        if let progress, isIndexing {
            let phase: String
            switch progress.phase {
            case .scanning: phase = "VERMESSE"
            case .indexing: phase = "INDIZIERE"
            case .saving: phase = "SPEICHERE"
            }

            drawText(phase, x: 14, y: 10, width: 80, font: 9, color: Theme.accent, bold: true)
            drawText(
                (progress.root as NSString).lastPathComponent,
                x: 96,
                y: 10,
                width: bounds.width - 190,
                font: 9,
                color: Theme.textDim
            )

            let percent = progress.phase == .scanning ? "..." : "\(Int((progress.fraction * 100).rounded())) %"
            drawText(percent, x: bounds.width - 100, y: 4, width: 86, font: 15, color: Theme.accent, bold: true, align: .right)

            let counts: String
            if progress.phase == .scanning {
                counts = "\(CSLFormat.count(progress.processed)) OBJEKTE"
            } else {
                counts = "\(CSLFormat.count(progress.processed)) / \(CSLFormat.count(progress.total)) DATEIEN"
            }
            drawText(counts, x: 14, y: 54, width: bounds.width - 230, font: 8, color: Theme.textDim)
            drawText("REST \(CSLFormat.eta(progress.eta))", x: bounds.width - 230, y: 54, width: 120, font: 8, color: Theme.textFaint, align: .right)

            if let item = progress.currentItem {
                drawText(item, x: 14, y: 72, width: bounds.width - 120, font: 8, color: Theme.textFaint)
            }
        } else if isIndexing {
            drawText("INDEX WIRD AUFGEBAUT", x: 14, y: 12, width: bounds.width - 28, font: 10, color: Theme.accent, bold: true)
            drawText("DATEIEN WERDEN GESAMMELT UND VORBEREITET.", x: 14, y: 54, width: bounds.width - 28, font: 8, color: Theme.textFaint)
        } else {
            drawText("INDEX", x: 14, y: 12, width: 80, font: 9, color: Theme.accent, bold: true)
            drawText("\(CSLFormat.count(totalEntries)) EINTRÄGE", x: bounds.width - 220, y: 11, width: 206, font: 9, color: Theme.textDim, align: .right)
            drawText("ORDNER WERDEN DIREKT DURCHSUCHT - OHNE SPOTLIGHT.", x: 14, y: 32, width: bounds.width - 28, font: 8, color: Theme.textFaint)
            let date = lastIndexed.map { CSLFormat.date($0) } ?? "NOCH NICHT INDIZIERT"
            drawText("ZULETZT: \(date)", x: 14, y: 54, width: bounds.width - 28, font: 8, color: Theme.textFaint)
        }
    }
}

private func drawButtonBackground(_ rect: CGRect, color: NSColor, border: NSColor) {
    PixelDraw.fill(rect, color)
    PixelDraw.frame(rect.insetBy(dx: 0.5, dy: 0.5), thickness: 1, color: border, notch: 2)
}

private func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: CGFloat, color: NSColor, bold: Bool = false, align: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = align
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
        .font: bold ? Theme.displayBold(font) : Theme.display(font),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    (text as NSString).draw(
        in: CGRect(x: x, y: y, width: width, height: font + 7),
        withAttributes: attributes
    )
}

// MARK: - Folder row

final class FolderRowView: SettingsRow {
    private let path: String
    private let meta: String
    private let missing: Bool
    private let name: String
    private let reindexButton: ClosureButton
    private let removeButton: ClosureButton

    init(
        path: String,
        count: Int,
        lastIndexed: Date?,
        formatter: SettingsSection,
        onReindex: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.path = path
        let url = URL(fileURLWithPath: path)
        name = url.lastPathComponent
        missing = !FileManager.default.fileExists(atPath: path)

        if missing {
            meta = "ORDNER FEHLT"
        } else if count > 0 {
            meta = "\(formatter.formatCount(count)) DATEIEN / ZULETZT \(formatter.formatDate(lastIndexed))"
        } else {
            meta = "NOCH NICHT INDIZIERT"
        }

        reindexButton = ClosureButton("NEU", style: .ghost, onTap: onReindex)
        removeButton = ClosureButton("X", style: .ghost, onTap: onRemove)

        super.init(height: 56)
        addSubview(reindexButton)
        addSubview(removeButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        reindexButton.frame = CGRect(x: bounds.width - 88, y: 16, width: 50, height: 24)
        removeButton.frame = CGRect(x: bounds.width - 32, y: 16, width: 24, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawText(name, x: 14, y: 7, width: bounds.width - 110, font: 12.5, color: missing ? Theme.danger : Theme.text, bold: true)
        drawText(PathDisplay.pretty(path), x: 14, y: 25, width: bounds.width - 110, font: 8.5, color: Theme.textFaint)
        drawText(meta, x: 14, y: 40, width: bounds.width - 110, font: 8, color: missing ? Theme.danger : Theme.accentDim)
    }
}

// MARK: - Folders section

final class FoldersSection: SettingsSection {
    private let card = IndexProgressCard()
    private let list = ScrollListView()
    private let addButton = ClosureButton("+ ORDNER HINZUFÜGEN", style: .primary) {}
    private let reindexAllButton = ClosureButton("ALLE NEU INDIZIEREN", style: .ghost) {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(card)
        addSubview(list)

        addButton.setAction { [weak self] in self?.addFolder() }
        reindexAllButton.setAction {
            IndexCoordinator.shared.indexAll()
        }
        addSubview(addButton)
        addSubview(reindexAllButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        addButton.frame = CGRect(x: bounds.width - 176, y: 0, width: 176, height: 28)
        card.frame = CGRect(x: 0, y: 64, width: bounds.width, height: 96)
        reindexAllButton.frame = CGRect(x: bounds.width - 138, y: 172, width: 138, height: 24)
        list.frame = CGRect(x: 0, y: 202, width: bounds.width, height: max(40, bounds.height - 202))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawHeader(
            title: "ORDNER INDIZIEREN",
            subtitle: "DIESE ORDNER WERDEN DIREKT DURCHSUCHT - SCHNELL, OHNE SPOTLIGHT."
        )
        drawText("INDIZIERTE ORDNER", x: 0, y: 178, width: 240, font: 8.5, color: Theme.textDim)
    }

    override func reload() {
        let store = SettingsStore.shared
        let index = FileIndex.shared

        var rows: [NSView] = []
        for folder in store.settings.indexedFolders {
            let row = FolderRowView(
                path: folder,
                count: index.count(forRoot: folder),
                lastIndexed: index.lastIndexed(forRoot: folder),
                formatter: self,
                onReindex: {
                    IndexCoordinator.shared.index(folder: folder)
                },
                onRemove: { [weak self] in
                    guard self != nil else { return }
                    SettingsStore.shared.removeIndexedFolder(folder)
                    IndexCoordinator.shared.removeFolder(folder)
                }
            )
            rows.append(row)
        }
        list.setRows(rows, rowHeight: 56, emptyText: "NOCH KEINE ORDNER INDIZIERT.")

        let lastDate = store.settings.indexedFolders
            .compactMap { index.lastIndexed(forRoot: $0) }
            .max()
        card.update(
            progress: IndexCoordinator.shared.latestProgress,
            isIndexing: IndexCoordinator.shared.isIndexing,
            totalEntries: index.totalCount,
            lastIndexed: lastDate
        )
        needsDisplay = true
    }

    override func updateIndexProgress(_ progress: FolderIndexer.Progress?) {
        card.setProgress(progress)
    }

    private func addFolder() {
        let urls = openPanel(
            prompt: "INDIZIEREN",
            message: "Ordner auswählen, die CSL direkt und ohne Spotlight durchsuchen soll."
        )
        guard !urls.isEmpty else { return }
        for url in urls {
            let path = SettingsStore.normalizeFolder(url.path)
            SettingsStore.shared.addIndexedFolder(path)
            IndexCoordinator.shared.index(folder: path)
        }
        reload()
    }
}
