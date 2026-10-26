import AppKit
import QuartzCore

final class PickerViewController: NSViewController, NSTextFieldDelegate {
    var brand: String = "CEP" {
        didSet {
            if isViewLoaded { rootView.logoText = brand }
        }
    }
    var onClose: (() -> Void)?
    /// Return `true` when the character was typed into the target app.
    var onInsert: ((EmojiItem, String) -> Bool)?

    private let store = EmojiStore.shared
    private let rootView = PickerRootView()
    private let searchField = PickerTextField(frame: .zero)
    private let placeholder = SearchPlaceholderView()
    private let prompt = SearchPromptView(frame: .zero)
    private let clearButton = ClearButton(frame: .zero)
    private let glowView = GlowView(frame: .zero)
    private let effectsView = InteractionEffectsView(frame: .zero)
    private let sidebar = CategorySidebarView()
    private let scrollView = NSScrollView()
    private let grid = EmojiGridView(frame: .zero)
    private let gridHeader = GridHeaderView(frame: .zero)
    private let skinTone = SkinToneView(frame: .zero)
    private let scrollIndicator = ScrollIndicatorView(frame: .zero)

    private var category: PickerCategory = .recent
    private var keyMonitor: Any?
    private var lastGridWidth: CGFloat = 0
    private var hoveredItem: EmojiItem?
    private var didBuild = false

    private var isSearching: Bool {
        !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard !didBuild else { return }
        didBuild = true

        rootView.wantsLayer = true
        rootView.logoText = brand
        rootView.isLoaded = store.isLoaded
        rootView.onOutsideClick = { [weak self] in
            self?.onClose?()
        }

        searchField.delegate = self
        searchField.onMouseDown = { [weak self] in self?.focus() }
        placeholder.text = "SEARCH EMOJI"
        clearButton.isHidden = true
        clearButton.onClick = { [weak self] in self?.clearSearch() }

        sidebar.onSelect = { [weak self] category in
            self?.chooseCategory(category, clearSearch: true)
        }
        skinTone.onSelect = { [weak self] tone in
            self?.skinToneChanged(tone)
        }

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = grid

        grid.onSelection = { [weak self] item in
            self?.hoveredItem = nil
            self?.updateFooterName()
        }
        grid.onHover = { [weak self] item in
            self?.hoveredItem = item
            self?.updateFooterName()
        }
        grid.onActivate = { [weak self] item, flags, point in
            self?.activate(item, modifiers: flags, point: point)
        }
        grid.onCopy = { [weak self] item in
            self?.copy(item)
        }
        grid.onCopyName = { [weak self] item in
            self?.copyName(item)
        }
        grid.onFavorite = { [weak self] item in
            self?.toggleFavorite(item)
        }

        scrollIndicator.scrollView = scrollView
        effectsView.onPointerMove = { [weak self] point in
            guard let self, point != nil else { return }
            self.grid.refreshHoverFromMouse()
        }

        view.addSubview(scrollView)
        view.addSubview(gridHeader)
        view.addSubview(sidebar)
        view.addSubview(searchField)
        view.addSubview(placeholder)
        view.addSubview(prompt)
        view.addSubview(clearButton)
        view.addSubview(skinTone)
        view.addSubview(scrollIndicator)
        view.addSubview(effectsView)
        view.addSubview(glowView)

        store.onStateChange = { [weak self] in
            self?.stateDidChange()
        }

        skinTone.tone = store.skinTone
        sidebar.selected = category
        installKeyMonitor()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // MARK: - Presentation

    func prewarm() {
        store.load()
        layoutViews()
        refresh(resetSelection: true)
        layoutViews()
    }

    func prepareForShow() {
        store.load()
        rootView.isLoaded = store.isLoaded
        layoutViews()

        searchField.stringValue = ""
        placeholder.isHidden = false
        clearButton.isHidden = true
        category = store.preferredCategory()
        sidebar.selected = category
        skinTone.tone = store.skinTone

        refresh(resetSelection: true)
        layoutViews()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        effectsView.activate()
        glowView.startPulse()
        sidebar.needsDisplay = true
        updateFooterName()
    }

    func prepareForHide() {
        effectsView.stop()
        glowView.stopPulse()
        prompt.stop()
    }

    func focus() {
        guard let window = view.window else { return }
        window.makeKey()
        window.makeFirstResponder(searchField)
        searchField.styleEditor()
    }

    // MARK: - Layout

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutViews()
    }

    private func layoutViews() {
        guard isViewLoaded else { return }
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        glowView.frame = bounds
        effectsView.frame = bounds

        let sidebarRect = Layout.sidebarRect(in: bounds)
        sidebar.frame = sidebarRect

        let headerRect = Layout.gridHeaderRect(in: bounds)
        skinTone.frame = Layout.skinToneRect(in: bounds)
        let reservedRight: CGFloat = skinTone.isHidden ? 0 : 120
        gridHeader.frame = CGRect(
            x: headerRect.minX + Theme.gridPadding,
            y: headerRect.minY,
            width: max(10, headerRect.width - 2 * Theme.gridPadding - reservedRight),
            height: headerRect.height
        )

        let gridRect = Layout.gridRect(in: bounds)
        scrollView.frame = gridRect
        scrollIndicator.frame = CGRect(
            x: gridRect.maxX - 7,
            y: gridRect.minY + 2,
            width: 7,
            height: max(0, gridRect.height - 4)
        )

        let fieldRect = Layout.searchFieldRect(in: bounds)
        searchField.frame = fieldRect
        placeholder.frame = fieldRect
        let promptCenter = Layout.promptCenter(in: bounds)
        prompt.frame = CGRect(
            x: promptCenter.x - 10,
            y: promptCenter.y - 10,
            width: 20,
            height: 20
        )
        clearButton.frame = Layout.clearButtonRect(in: bounds)

        grid.minimumHeight = gridRect.height
        let widthChanged = abs(lastGridWidth - gridRect.width) > 0.5
        if widthChanged || grid.contentHeight < gridRect.height {
            lastGridWidth = gridRect.width
            grid.layoutFrames(width: gridRect.width, minimumHeight: gridRect.height)
            grid.frame = CGRect(x: 0, y: 0, width: gridRect.width, height: grid.contentHeight)
            scrollIndicator.update()
        } else if abs(grid.frame.height - grid.contentHeight) > 0.5 {
            grid.frame = CGRect(x: 0, y: 0, width: gridRect.width, height: grid.contentHeight)
        }

        glowView.needsDisplay = true
        effectsView.needsLayout = true
    }

    // MARK: - Refresh

    private func refresh(resetSelection: Bool) {
        guard isViewLoaded else { return }
        let query = searchField.stringValue
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searching = !trimmed.isEmpty

        let items: [EmojiItem]
        if searching {
            items = store.search(trimmed)
            gridHeader.title = "SEARCH  \"\(trimmed.uppercased())\""
        } else {
            category = valid(category)
            items = store.items(for: category)
            gridHeader.title = category.longTitle
        }

        if !store.isLoaded {
            grid.emptyTitle = "LOADING CHARACTERS"
            grid.emptySubtitle = "ONE MOMENT"
        } else if searching {
            grid.emptyTitle = "NO MATCH"
            grid.emptySubtitle = "\"\(trimmed.uppercased())\" NOT FOUND"
        } else if category == .recent {
            grid.emptyTitle = "NO RECENT EMOJI"
            grid.emptySubtitle = "PICK ONE TO START"
        } else if category == .favorites {
            grid.emptyTitle = "NO FAVORITES"
            grid.emptySubtitle = "CMD+CLICK TO PIN"
        } else {
            grid.emptyTitle = "NOTHING HERE"
            grid.emptySubtitle = "TRY ANOTHER CATEGORY"
        }

        grid.updateFavoriteLookup(store.state.favoriteLookup)
        grid.setItems(items, resetSelection: resetSelection)

        gridHeader.count = items.count
        gridHeader.isSearching = searching
        rootView.categoryTitle = gridHeader.title
        rootView.resultCount = items.count
        rootView.isSearching = searching
        rootView.query = query
        placeholder.isHidden = !query.isEmpty
        clearButton.isHidden = query.isEmpty

        let shouldHideTone = !(searching || category.supportsSkinTone)
        if skinTone.isHidden != shouldHideTone {
            skinTone.isHidden = shouldHideTone
            layoutViews()
        }

        sidebar.selected = category
        updateSidebarCounts()
        updateFooterName()
        scrollIndicator.update()
        if resetSelection {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        rootView.needsDisplay = true
        gridHeader.needsDisplay = true
    }

    private func valid(_ category: PickerCategory) -> PickerCategory {
        if category == .recent, store.state.recents.isEmpty, isSearching == false {
            return .recent
        }
        return category
    }

    private func updateSidebarCounts() {
        var counts: [PickerCategory: Int] = [:]
        for category in PickerCategory.allCases {
            counts[category] = store.count(for: category)
        }
        sidebar.counts = counts
    }

    private func updateFooterName() {
        let item = hoveredItem ?? grid.selectedItem
        rootView.selectedName = item?.displayName ?? ""
        rootView.needsDisplay = true
    }

    private func stateDidChange() {
        guard isViewLoaded else { return }
        grid.updateFavoriteLookup(store.state.favoriteLookup)
        skinTone.tone = store.skinTone
        updateSidebarCounts()
        if category == .favorites, !isSearching {
            refresh(resetSelection: false)
        } else if category == .recent, !isSearching {
            // Keep the visible recent list stable while the panel is open;
            // the new order is applied the next time the picker opens.
            gridHeader.count = store.items(for: .recent).count
            rootView.resultCount = gridHeader.count
        }
        updateFooterName()
    }

    // MARK: - Search field

    func controlTextDidChange(_ notification: Notification) {
        placeholder.isHidden = !searchField.stringValue.isEmpty
        clearButton.isHidden = searchField.stringValue.isEmpty
        prompt.pulse()
        effectsView.inputPulse()
        refresh(resetSelection: true)
    }

    // MARK: - Actions

    private func activate(_ item: EmojiItem, modifiers: NSEvent.ModifierFlags, point: CGPoint) {
        Log.debug("activate \(item.text) modifiers=\(modifiers.rawValue)")
        let rootPoint = grid.convert(point, to: view)
        effectsView.click(at: rootPoint)

        if modifiers.contains(.command) {
            toggleFavorite(item)
            return
        }

        let text = store.insertionText(for: item)
        let inserted = onInsert?(item, text) ?? false
        if inserted {
            store.recordUse(item)
            rootView.flashStatus("INSERTED", color: Theme.success)
            effectsView.inputPulse(success: true)
            prompt.pulse()
        } else {
            TextInjector.copyToPasteboard(text)
            store.recordUse(item)
            rootView.flashStatus("COPIED / NO TARGET", color: Theme.danger, duration: 1.5)
            effectsView.inputPulse(success: false)
        }
        grid.flash()
        updateSidebarCounts()
        updateFooterName()
        DispatchQueue.main.async { [weak self] in
            self?.focus()
        }
    }

    private func copy(_ item: EmojiItem) {
        TextInjector.copyToPasteboard(store.insertionText(for: item))
        store.recordUse(item)
        rootView.flashStatus("COPIED", color: Theme.accent)
        effectsView.inputPulse(success: true)
        grid.flash()
        updateSidebarCounts()
        focus()
    }

    private func copyName(_ item: EmojiItem) {
        TextInjector.copyToPasteboard(item.name)
        rootView.flashStatus("NAME COPIED", color: Theme.accent)
        effectsView.inputPulse(success: true)
        focus()
    }

    private func toggleFavorite(_ item: EmojiItem) {
        store.toggleFavorite(item)
        let pinned = store.isFavorite(item)
        rootView.flashStatus(pinned ? "PINNED" : "UNPINNED", color: pinned ? Theme.accent : Theme.textDim)
        grid.flash()
        focus()
    }

    private func skinToneChanged(_ tone: Int) {
        store.setSkinTone(tone)
        skinTone.tone = store.skinTone
        let names = ["DEFAULT", "LIGHT", "MEDIUM LIGHT", "MEDIUM", "MEDIUM DARK", "DARK"]
        let name = names.indices.contains(tone) ? names[tone] : "DEFAULT"
        rootView.flashStatus("TONE / \(name)", color: Theme.accent, duration: 0.8)
        effectsView.inputPulse(success: true)
        focus()
    }

    private func clearSearch() {
        searchField.stringValue = ""
        placeholder.isHidden = false
        clearButton.isHidden = true
        prompt.pulse()
        refresh(resetSelection: true)
        focus()
    }

    private func chooseCategory(_ newCategory: PickerCategory, clearSearch: Bool) {
        if clearSearch, !searchField.stringValue.isEmpty {
            searchField.stringValue = ""
            placeholder.isHidden = false
            clearButton.isHidden = true
        }
        category = newCategory
        store.setLastCategory(newCategory)
        sidebar.selected = newCategory
        refresh(resetSelection: true)
        focus()
    }

    private func cycleCategory(direction: Int) {
        let all = PickerCategory.allCases
        guard let index = all.firstIndex(of: category) else { return }
        let target = (index + direction + all.count) % all.count
        chooseCategory(all[target], clearSearch: true)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.view.window,
                  window.isVisible,
                  window.isKeyWindow else {
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = flags.contains(.command)

            switch event.keyCode {
            case 53: // escape
                self.onClose?()
                return nil

            case 36, 76: // return / keypad enter
                if hasCommand {
                    if let item = self.grid.selectedItem { self.copy(item) }
                } else if let item = self.grid.selectedItem {
                    self.activate(item, modifiers: [], point: self.grid.selectedItemPoint)
                }
                return nil

            case 126: // up
                self.grid.moveVertical(-1)
                return nil

            case 125: // down
                self.grid.moveVertical(1)
                return nil

            case 123: // left
                if self.searchField.stringValue.isEmpty {
                    self.grid.moveHorizontal(-1)
                    return nil
                }
                return event

            case 124: // right
                if self.searchField.stringValue.isEmpty {
                    self.grid.moveHorizontal(1)
                    return nil
                }
                return event

            case 48: // tab
                self.cycleCategory(direction: flags.contains(.shift) ? -1 : 1)
                return nil

            case 116: // page up
                self.grid.movePage(-1)
                return nil

            case 121: // page down
                self.grid.movePage(1)
                return nil

            case 115: // home
                self.grid.selectFirst()
                return nil

            case 119: // end
                self.grid.selectLast()
                return nil

            case 2: // D
                if hasCommand, let item = self.grid.selectedItem {
                    self.toggleFavorite(item)
                    return nil
                }
                return event

            default:
                return event
            }
        }
    }

    // MARK: - Test / debugging entry points

    func setSearchText(_ text: String) {
        searchField.stringValue = text
        placeholder.isHidden = !text.isEmpty
        clearButton.isHidden = text.isEmpty
        refresh(resetSelection: true)
    }

    func setCategory(named name: String) {
        guard let category = PickerCategory(rawValue: name.lowercased()) else { return }
        chooseCategory(category, clearSearch: true)
    }

    func setSkinTone(_ tone: Int) {
        skinToneChanged(tone)
    }

    func showStatus(_ text: String) {
        rootView.flashStatus(text, color: Theme.accent)
    }

    var debugItemCount: Int { grid.selectedItem == nil ? 0 : 1 }
    var debugSelectedName: String { grid.selectedItem?.displayName ?? "none" }
    var debugCategory: String { category.rawValue }
    var debugQuery: String { searchField.stringValue }
    var debugVisibleItems: Int {
        var count = 0
        for _ in grid.items { count += 1 }
        return count
    }
}

private extension EmojiGridView {
    var selectedItemPoint: CGPoint {
        guard let frame = selectedFrame else { return CGPoint(x: 20, y: 20) }
        return CGPoint(x: frame.midX, y: frame.midY)
    }
}
