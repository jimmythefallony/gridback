import AppKit
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
        panel.setFrame(screen.frame, display: true)
        panel.alphaValue = 1
        NSApp.unhide(nil)
        NSApp.activate()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        let frame = panel.frame
        log.info("Panel ordered front visible=\(panel.isVisible, privacy: .public) occlusion=\(panel.occlusionState.rawValue, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public) screen=\(NSStringFromRect(screen.frame), privacy: .public) level=\(panel.level.rawValue, privacy: .public)")
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func relayoutIfVisible() {
        guard let panel, panel.isVisible, let screen = PrimaryDisplay.screen() else { return }
        panel.setFrame(screen.frame, display: true)
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
