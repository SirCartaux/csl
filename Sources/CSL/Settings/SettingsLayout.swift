import AppKit

enum SettingsLayout {
    static var windowSize: NSSize {
        NSSize(
            width: Theme.settingsWidth + 2 * Theme.settingsInset,
            height: Theme.settingsHeight + 2 * Theme.settingsInset
        )
    }

    static func panelRect(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: Theme.settingsInset, dy: Theme.settingsInset)
    }

    static func headerRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        return CGRect(
            x: panel.minX,
            y: panel.minY,
            width: panel.width,
            height: Theme.settingsHeaderHeight
        )
    }

    static func sidebarRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        let header = headerRect(in: bounds)
        return CGRect(
            x: panel.minX,
            y: header.maxY,
            width: Theme.settingsSidebarWidth,
            height: panel.maxY - header.maxY
        )
    }

    static func contentRect(in bounds: CGRect) -> CGRect {
        let panel = panelRect(in: bounds)
        let header = headerRect(in: bounds)
        let sidebar = sidebarRect(in: bounds)
        return CGRect(
            x: sidebar.maxX,
            y: header.maxY,
            width: panel.maxX - sidebar.maxX,
            height: panel.maxY - header.maxY
        )
    }

    static func bodyRect(in bounds: CGRect) -> CGRect {
        contentRect(in: bounds).insetBy(dx: 24, dy: 20)
    }
}
