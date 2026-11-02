import AppKit
import GridBackCore
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var model: GridBackModel?
    private var monitor: Any?
    private var settingsWindow: NSWindow?

    func show(model: GridBackModel) {
        self.model = model
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "GridBack Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 460, height: 280))
            window.level = .floating
            settingsWindow = window
        }
        NSApp.unhide(nil)
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool {
        settingsWindow?.isVisible == true
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func stopRecording() {
        monitor.map { NSEvent.removeMonitor($0) }
        monitor = nil
        model?.cancelShortcutRecording()
    }

    /// Called from the app-wide key monitor while the settings window is key.
    func consumeRecordingKey(_ event: NSEvent) -> Bool {
        guard model?.isRecordingShortcut == true, settingsWindow?.isKeyWindow == true else {
            return false
        }
        if event.isARepeat {
            return true
        }
        if event.keyCode == SearchKeyRouting.escapeKeyCode {
            stopRecording()
            return true
        }
        switch ShortcutCapture.interpret(event) {
        case .success(let chord):
            model?.tryAdoptShortcut(chord)
        case .failure(let rejection):
            model?.noteShortcutRejection(rejection)
        }
        return true
    }
}
