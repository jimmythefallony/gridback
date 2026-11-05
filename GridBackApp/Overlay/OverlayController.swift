import AppKit
import GridBackCore
import os
import SwiftUI

/// Owns the single overlay panel and moves it onto the primary display.
/// Use this on the main thread.
final class OverlayController: NSObject {
    private var panel: OverlayPanel?
    private var model: GridBackModel?
    private var screenObserver: NSObjectProtocol?
    /// True while this overlay is keeping an auto-hidden menu bar from being revealed.
    private var menuBarSuppressed = false
    /// Bumps on each show so a delayed hide cannot reveal the bar for a newer open.
    private var menuBarGeneration = 0
    /// One dismiss per open. Toggling twice would show the system launcher again.
    private var didDismissSystemLauncher = false
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "overlay")

    func attach(model: GridBackModel) {
        self.model = model
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.relayoutIfVisible()
            }
        }
    }

    func show() {
        guard let model else {
            log.error("Show skipped: overlay has no model")
            return
        }
        guard let screen = PrimaryDisplay.screen() else {
            log.error("Show skipped: no primary display")
            return
        }
        let panel = self.panel ?? makePanel(on: screen, model: model)
        self.panel = panel
        // Re-apply after any AppKit floating-panel adjustment so the real Dock
        // stays the window in front. Dock preferences are not touched.
        panel.level = OverlayPanel.overlayLevel
        panel.setFrame(screen.frame, display: true)
        // Read this before activation. Activating an accessory app reveals the
        // menu bar, and visibleFrame would then report a top inset that the
        // user did not reserve.
        let reserve = ScreenReserveReader.current(on: screen)
        model.updateScreenReserve(reserve)
        // presentationOptions cannot hide only the menu bar: autoHideMenuBar
        // is legal only together with a Dock hide flag, which would change the
        // Dock. NSMenu.setMenuBarVisible is per-app and leaves Dock prefs alone.
        menuBarGeneration += 1
        let generation = menuBarGeneration
        menuBarSuppressed = !reserve.menuBarReservesSpace
        if menuBarSuppressed {
            NSMenu.setMenuBarVisible(false)
        }
        // The system launcher can open with us, or already be underneath.
        // Close it before we take the keyboard, and only once: the Dock
        // notification toggles, so a second send would open it again.
        didDismissSystemLauncher = false
        dismissSystemLauncherIfNeeded()
        panel.alphaValue = 1
        NSApp.unhide(nil)
        // Cooperative activate() does not steal the keyboard from Launchpad,
        // so Escape and typing never arrive until a later click.
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.level = OverlayPanel.overlayLevel
        if menuBarSuppressed {
            NSMenu.setMenuBarVisible(false)
        }
        let frame = panel.frame
        log.info("Panel ordered front visible=\(panel.isVisible, privacy: .public) occlusion=\(panel.occlusionState.rawValue, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public) screen=\(NSStringFromRect(screen.frame), privacy: .public) level=\(panel.level.rawValue, privacy: .public) reserve top=\(reserve.top, privacy: .public) left=\(reserve.left, privacy: .public) bottom=\(reserve.bottom, privacy: .public) right=\(reserve.right, privacy: .public) menuBarSuppressed=\(self.menuBarSuppressed, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.menuBarGeneration == generation, self.panel?.isVisible == true else { return }
            self.claimKeyboard()
            self.keepAutoHiddenMenuBarHidden()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.menuBarGeneration == generation, self.panel?.isVisible == true else { return }
            self.dismissSystemLauncherIfNeeded()
            self.claimKeyboard()
        }
    }

    func hide() {
        // If the system launcher is still underneath, close it with us so a
        // background click does not dismiss into Launchpad.
        dismissSystemLauncherIfNeeded()
        panel?.orderOut(nil)
        let generation = menuBarGeneration
        // Restore after the app resigns so the bar does not flash while we
        // are still the active app. System Settings are not written.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.menuBarGeneration == generation else { return }
            self.releaseMenuBarSuppression()
        }
    }

    private func claimKeyboard() {
        guard panel?.isVisible == true else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    private func dismissSystemLauncherIfNeeded() {
        guard !didDismissSystemLauncher else { return }
        guard SystemLauncherProbe.isVisible() else { return }
        didDismissSystemLauncher = true
        coreDockSendNotification("com.apple.launchpad.toggle" as CFString)
        log.info("Dismissed the system launcher that was open with the grid")
    }

    private func keepAutoHiddenMenuBarHidden() {
        guard menuBarSuppressed, panel?.isVisible == true else { return }
        NSMenu.setMenuBarVisible(false)
    }

    private func releaseMenuBarSuppression() {
        guard menuBarSuppressed else { return }
        menuBarSuppressed = false
        NSMenu.setMenuBarVisible(true)
    }

    private func relayoutIfVisible() {
        guard let panel, panel.isVisible, let screen = PrimaryDisplay.screen(), let model else { return }
        panel.level = OverlayPanel.overlayLevel
        panel.setFrame(screen.frame, display: true)
        var reserve = ScreenReserveReader.current(on: screen)
        if menuBarSuppressed {
            reserve.top = 0
        }
        model.updateScreenReserve(reserve)
    }

    private func makePanel(on screen: NSScreen, model: GridBackModel) -> OverlayPanel {
        let panel = OverlayPanel(screen: screen)
        let effect = NSVisualEffectView(frame: panel.contentView?.bounds ?? screen.frame)
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        panel.contentView = effect
        return panel
    }
}

@_silgen_name("CoreDockSendNotification")
private func coreDockSendNotification(_ name: CFString)

enum SystemLauncherProbe {
    /// Window metadata only. Does not read pixels or change Dock settings.
    static func isVisible() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let launcherRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == SystemLauncherVisibility.launcherBundleID
        }
        let screen = PrimaryDisplay.screen()?.frame ?? .zero
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = raw.map { item in
            let bounds = item[kCGWindowBounds as String] as? [String: Any] ?? [:]
            return SystemLauncherWindow(
                owner: item[kCGWindowOwnerName as String] as? String ?? "",
                name: item[kCGWindowName as String] as? String ?? "",
                memoryBytes: intValue(item[kCGWindowMemoryUsage as String]),
                width: doubleValue(bounds["Width"]),
                height: doubleValue(bounds["Height"])
            )
        }
        return SystemLauncherVisibility.isVisible(
            frontmostBundleID: frontmost,
            launcherProcessRunning: launcherRunning,
            windows: windows,
            screenWidth: Double(screen.width),
            screenHeight: Double(screen.height)
        )
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return 0
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        return 0
    }
}

enum ScreenReserveReader {
    /// Reads the screen geometry AppKit already publishes. Does not write Dock settings.
    static func current(on screen: NSScreen) -> ScreenReserve {
        let screenFrame = screen.frame
        let visible = screen.visibleFrame
        return ScreenReserve.occupying(
            screenX: Double(screenFrame.origin.x),
            screenY: Double(screenFrame.origin.y),
            screenWidth: Double(screenFrame.size.width),
            screenHeight: Double(screenFrame.size.height),
            visibleX: Double(visible.origin.x),
            visibleY: Double(visible.origin.y),
            visibleWidth: Double(visible.size.width),
            visibleHeight: Double(visible.size.height)
        )
    }
}
