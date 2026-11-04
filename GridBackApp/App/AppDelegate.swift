import AppKit
import GridBackCore
import os

@main
final class AppDelegate: NSObject, NSApplicationDelegate, GridBackUIDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private let overlay = OverlayController()
    private let settings = SettingsWindowController()
    private var menuBar: MenuBarController?
    private var keyMonitor: Any?
    private let model = GridBackModel.shared
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let policyBefore = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        log.info("Launch policy before=\(policyBefore.rawValue, privacy: .public) after=\(NSApp.activationPolicy().rawValue, privacy: .public)")
        model.delegate = self
        overlay.attach(model: model)
        let menu = MenuBarController(model: model)
        menuBar = menu
        installKeyMonitor()
        model.start()
        log.info("Hotkey status \(self.model.hotkeyFailure ?? "registered", privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func gridBackShowOverlay() {
        overlay.show()
    }

    func gridBackHideOverlay() {
        overlay.hide()
        if !settings.isVisible {
            NSApp.hide(nil)
        }
    }

    func gridBackShowSettings() {
        settings.show(model: model)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.settings.consumeRecordingKey(event) {
                return nil
            }
            let modifiers = KeyModifiers(eventFlags: event.modifierFlags)
            let characters = event.characters ?? ""
            if self.searchFieldIsEditing {
                let action = SearchKeyRouting.action(
                    keyCode: event.keyCode,
                    characters: characters,
                    modifiers: modifiers,
                    isSearching: self.model.isSearching,
                    columns: self.model.layout.metrics.columns
                )
                switch action {
                case .startOrAppend, .backspace:
                    return event
                default:
                    break
                }
            }
            if self.model.handleKeyDown(keyCode: event.keyCode, characters: characters, modifiers: modifiers) {
                return nil
            }
            return event
        }
    }

    /// The search pill uses a text field. While it is focused, letters and
    /// delete belong to that field so the cursor stays in sync.
    private var searchFieldIsEditing: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }
}
