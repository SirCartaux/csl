import AppKit

enum AliasPrompt {
    /// Prompt for a custom search word and persist it for this app/file.
    @discardableResult
    static func addAlias(for url: URL, title: String) -> SearchAlias? {
        let alert = NSAlert()
        alert.messageText = "ADD ALIAS"
        alert.informativeText = "Give “\(title)” a custom name. Type that name in the launcher to find it."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "ADD")
        alert.addButton(withTitle: "CANCEL")

        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "ALIAS, E.G. BROWSER"
        field.font = Theme.display(12)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        switch AliasStore.shared.add(alias: field.stringValue, targetURL: url, targetName: title) {
        case .success(let alias):
            return alias
        case .failure(let error):
            let failure = NSAlert()
            failure.messageText = "ALIAS NOT ADDED"
            failure.informativeText = error.localizedDescription
            failure.alertStyle = .warning
            failure.addButton(withTitle: "OK")
            failure.runModal()
            return nil
        }
    }
}
