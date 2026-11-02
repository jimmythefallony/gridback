import AppKit
import GridBackCore

final class AppDelegate: NSObject, NSApplicationDelegate, GridBackUIDelegate {
    private let overlay = OverlayController()
    private let settings = SettingsWindowController()
    private var keyMonitor: Any?
    private let model = GridBackModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.delegate = self
        overlay.attach(model: model)
        installKeyMonitor()
        model.start()
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
            if self.model.handleKeyDown(keyCode: event.keyCode, characters: characters, modifiers: modifiers) {
                return nil
            }
            return event
        }
    }
}
