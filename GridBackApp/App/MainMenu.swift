import AppKit

/// Installs a main menu so text fields receive the standard Edit shortcuts.
///
/// An accessory app has no menu bar, and AppKit only matches Command shortcuts
/// against a menu. The first item is the application-menu slot and stays empty.
/// Calling this does not change the activation policy.
enum MainMenu {
    static func install() {
        let main = NSMenu()

        let applicationSlot = NSMenuItem()
        applicationSlot.submenu = NSMenu()
        main.addItem(applicationSlot)

        let editSlot = NSMenuItem()
        editSlot.submenu = editMenu()
        main.addItem(editSlot)

        NSApp.mainMenu = main
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Edit"))
        menu.addItem(item(String(localized: "Undo"), action: Selector(("undo:")), key: "z"))
        menu.addItem(item(
            String(localized: "Redo"),
            action: Selector(("redo:")),
            key: "z",
            modifiers: [.command, .shift]
        ))
        menu.addItem(item(String(localized: "Cut"), action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item(String(localized: "Copy"), action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item(String(localized: "Paste"), action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item(String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func item(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}
