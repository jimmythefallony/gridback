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
        let reserve = ScreenReserveReader.current(on: screen)
        model.updateScreenReserve(reserve)
        panel.alphaValue = 1
        NSApp.unhide(nil)
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.level = OverlayPanel.overlayLevel
        let frame = panel.frame
        log.info("Panel ordered front visible=\(panel.isVisible, privacy: .public) occlusion=\(panel.occlusionState.rawValue, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public) screen=\(NSStringFromRect(screen.frame), privacy: .public) level=\(panel.level.rawValue, privacy: .public) reserve top=\(reserve.top, privacy: .public) left=\(reserve.left, privacy: .public) bottom=\(reserve.bottom, privacy: .public) right=\(reserve.right, privacy: .public)")
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func relayoutIfVisible() {
        guard let panel, panel.isVisible, let screen = PrimaryDisplay.screen(), let model else { return }
        panel.level = OverlayPanel.overlayLevel
        panel.setFrame(screen.frame, display: true)
        model.updateScreenReserve(ScreenReserveReader.current(on: screen))
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
