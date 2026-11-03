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
    private var eventMonitors: [Any] = []
    private var pageSwipe = PageSwipeTracker()
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
        installEventMonitors()
        model.start()
        log.info("Hotkey status \(self.model.hotkeyFailure ?? "registered", privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    func gridBackShowOverlay() {
        overlay.show()
    }

    func gridBackHideOverlay() {
        pageSwipe.reset()
        overlay.hide()
        if !settings.isVisible {
            NSApp.hide(nil)
        }
    }

    func gridBackShowSettings() {
        settings.show(model: model)
    }

    private func installEventMonitors() {
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
        let scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event)
        }
        eventMonitors.append(contentsOf: [keyMonitor, scrollMonitor].compactMap { $0 })
    }

    /// Two-finger trackpad swipes turn the page. A mouse wheel is left alone.
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard model.isOverlayVisible, !model.isSearching else {
            pageSwipe.reset()
            return event
        }
        guard event.hasPreciseScrollingDeltas, let phase = swipePhase(from: event.phase) else {
            return event
        }
        if let turn = pageSwipe.update(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            phase: phase
        ) {
            switch turn {
            case .previous:
                model.selectPage(model.currentPage - 1)
            case .next:
                model.selectPage(model.currentPage + 1)
            }
        }
        return nil
    }

    private func swipePhase(from phase: NSEvent.Phase) -> PageSwipePhase? {
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.began) { return .began }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.changed) || phase.contains(.stationary) { return .changed }
        return nil
    }
}
