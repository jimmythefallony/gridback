import AppKit
import os

/// Menu bar icon backed by AppKit.
///
/// SwiftUI `MenuBarExtra` draws an icon on macOS 26, but the status item it
/// creates has no menu. Clicks then do nothing. An `NSStatusItem` menu opens
/// on the normal click.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: GridBackModel
    private let statusItem: NSStatusItem
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "menu")

    init(model: GridBackModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: String(localized: "GridBack")
            )
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.setAccessibilityLabel(String(localized: "GridBack"))
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        log.info("Status item visible=\(self.statusItem.isVisible, privacy: .public)")
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        add(String(localized: "Open GridBack"), to: menu, action: #selector(openGrid))
        add(String(localized: "Settings…"), to: menu, action: #selector(openSettings))
        menu.addItem(.separator())
        let shortcut = NSMenuItem(title: model.shortcutMenuTitle, action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        if let failure = model.hotkeyFailure {
            let failureItem = NSMenuItem(title: failure, action: nil, keyEquivalent: "")
            failureItem.isEnabled = false
            menu.addItem(failureItem)
        }
        if let warning = model.persistenceWarning {
            let warningItem = NSMenuItem(title: warning, action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }
        menu.addItem(.separator())
        add(String(localized: "Quit GridBack"), to: menu, action: #selector(quit))
        let titles = menu.items.map(\.title).joined(separator: " | ")
        log.info("Menu opened: \(titles, privacy: .public)")
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func openGrid() {
        model.showOverlay()
    }

    @objc private func openSettings() {
        model.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
