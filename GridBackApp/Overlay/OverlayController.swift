import AppKit
import CoreImage
import GridBackCore
import os
import SwiftUI

/// Owns the single overlay panel and moves it onto the primary display.
/// Use this on the main thread.
final class OverlayController: NSObject {
    private var panel: OverlayPanel?
    private var menuBarCover: MenuBarCoverPanel?
    private var model: GridBackModel?
    private var screenObserver: NSObjectProtocol?
    /// True while this overlay is keeping an auto-hidden menu bar from being revealed.
    private var menuBarSuppressed = false
    /// Presentation options from before this overlay touched them. Restored on close.
    private var savedPresentationOptions: NSApplication.PresentationOptions?
    /// Bumps on each show so a delayed hide cannot reveal the bar for a newer open.
    private var menuBarGeneration = 0
    /// One dismiss per open. Toggling twice would show the system launcher again.
    private var didDismissSystemLauncher = false
    private var escapeMonitor: Any?
    private var activationObserver: NSObjectProtocol?
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
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.otherApplicationDidActivate(notification)
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
        var reserve = ScreenReserveReader.current(on: screen)
        // A revealed auto-hide bar still has a top inset. The preference, not
        // that momentary inset, decides whether we keep it hidden.
        menuBarSuppressed = MenuBarSuppression.shouldSuppress(
            menuBarReservesSpace: reserve.menuBarReservesSpace,
            userAutoHidesMenuBar: MenuBarPreference.userAutoHidesMenuBar
        )
        if menuBarSuppressed {
            reserve.top = 0
        }
        model.updateScreenReserve(reserve)
        // setMenuBarVisible(false) sets hideDock as well as hideMenuBar.
        // autoHideMenuBar alone does not hide the Dock, and on this OS it takes
        // effect while GridBack stays an accessory app. Switching to .regular
        // would flash a Dock icon.
        menuBarGeneration += 1
        let generation = menuBarGeneration
        // The system launcher can open with us, or already be underneath.
        // Close it before we take the keyboard, and only once: the Dock
        // notification toggles, so a second send would open it again.
        didDismissSystemLauncher = false
        dismissSystemLauncherIfNeeded()
        panel.alphaValue = 1
        updateMenuBarCover(on: screen)
        NSApp.unhide(nil)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.level = OverlayPanel.overlayLevel
        claimKeyboard()
        updateMenuBarCover(on: screen)
        let frame = panel.frame
        installEscapeMonitor()
        log.info("Panel ordered front visible=\(panel.isVisible, privacy: .public) occlusion=\(panel.occlusionState.rawValue, privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public) screen=\(NSStringFromRect(screen.frame), privacy: .public) level=\(panel.level.rawValue, privacy: .public) reserve top=\(reserve.top, privacy: .public) left=\(reserve.left, privacy: .public) bottom=\(reserve.bottom, privacy: .public) right=\(reserve.right, privacy: .public) menuBarSuppressed=\(self.menuBarSuppressed, privacy: .public) options=\(NSApp.presentationOptions.rawValue, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.menuBarGeneration == generation, self.panel?.isVisible == true else { return }
            self.claimKeyboard()
            self.keepAutoHiddenMenuBarHidden()
            if let screen = PrimaryDisplay.screen() {
                self.updateMenuBarCover(on: screen)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.menuBarGeneration == generation, self.panel?.isVisible == true else { return }
            self.dismissSystemLauncherIfNeeded()
            self.claimKeyboard()
            if let screen = PrimaryDisplay.screen() {
                self.updateMenuBarCover(on: screen)
            }
        }
    }

    func hide() {
        removeEscapeMonitor()
        // If the system launcher is still underneath, close it with us so a
        // background click does not dismiss into Launchpad.
        dismissSystemLauncherIfNeeded()
        menuBarCover?.orderOut(nil)
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
        // Stay accessory for the whole lifetime so GridBack never appears in
        // the Dock or in Command-Tab. autoHideMenuBar is applied around
        // activation and never adds a Dock-hide flag.
        applyMenuBarPolicy()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
        applyMenuBarPolicy()
    }

    private func otherApplicationDidActivate(_ notification: Notification) {
        guard panel?.isVisible == true, let model else { return }
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return
        }
        if let own = Bundle.main.bundleIdentifier, app.bundleIdentifier == own {
            return
        }
        // The Dock process itself is not the app the user just launched.
        if app.bundleIdentifier == SystemLauncherVisibility.dockBundleID {
            return
        }
        let bundle = app.bundleIdentifier ?? "unknown"
        log.info("Hiding grid because \(bundle, privacy: .public) became active")
        model.hideOverlay()
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                return
            }
            DispatchQueue.main.async {
                guard self?.panel?.isVisible == true else { return }
                self?.model?.hideOverlay()
            }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func dismissSystemLauncherIfNeeded() {
        guard !didDismissSystemLauncher else { return }
        guard SystemLauncherProbe.isVisible() else { return }
        didDismissSystemLauncher = true
        coreDockSendNotification("com.apple.launchpad.toggle" as CFString)
        log.info("Dismissed the system launcher that was open with the grid")
    }

    private func applyMenuBarPolicy() {
        guard menuBarSuppressed else { return }
        if savedPresentationOptions == nil {
            savedPresentationOptions = NSApp.presentationOptions
        }
        let updated = NSApplication.PresentationOptions(rawValue: MenuBarPresentation.keepingDockVisible(
            current: NSApp.presentationOptions.rawValue,
            suppressAutoHiddenMenuBar: true
        ))
        var safe = updated
        let baseline = savedPresentationOptions ?? NSApp.presentationOptions
        if !baseline.contains(.hideDock) {
            safe.remove(.hideDock)
        }
        if !baseline.contains(.autoHideDock) {
            safe.remove(.autoHideDock)
        }
        if NSApp.presentationOptions != safe {
            NSApp.presentationOptions = safe
        }
    }

    private func keepAutoHiddenMenuBarHidden() {
        guard menuBarSuppressed, panel?.isVisible == true else { return }
        applyMenuBarPolicy()
    }

    private func releaseMenuBarSuppression() {
        guard menuBarSuppressed || savedPresentationOptions != nil else { return }
        menuBarSuppressed = false
        if let saved = savedPresentationOptions {
            NSApp.presentationOptions = saved
            savedPresentationOptions = nil
        }
    }

    private func relayoutIfVisible() {
        guard let panel, panel.isVisible, let screen = PrimaryDisplay.screen(), let model else { return }
        panel.level = OverlayPanel.overlayLevel
        panel.setFrame(screen.frame, display: true)
        updateMenuBarCover(on: screen)
        var reserve = ScreenReserveReader.current(on: screen)
        if menuBarSuppressed {
            reserve.top = 0
        }
        model.updateScreenReserve(reserve)
    }

    private func updateMenuBarCover(on screen: NSScreen) {
        guard let panel else { return }
        guard let backdrop = MenuBarCoverImage.backdrop(on: screen) else {
            panel.backdropView.image = nil
            panel.backdropView.isHidden = true
            panel.fallbackBlur.isHidden = false
            menuBarCover?.orderOut(nil)
            return
        }
        panel.fallbackBlur.isHidden = true
        panel.backdropView.isHidden = false
        panel.backdropView.image = backdrop.full
        guard menuBarSuppressed, panel.isVisible else {
            menuBarCover?.orderOut(nil)
            return
        }
        let cover = menuBarCover ?? MenuBarCoverPanel(screen: screen)
        menuBarCover = cover
        cover.show(snapshot: backdrop.strip, on: screen, height: backdrop.stripPointHeight)
    }

    private func makePanel(on screen: NSScreen, model: GridBackModel) -> OverlayPanel {
        let panel = OverlayPanel(screen: screen)
        let bounds = NSRect(origin: .zero, size: screen.frame.size)
        let container = NSView(frame: bounds)
        container.autoresizingMask = [.width, .height]
        panel.fallbackBlur.frame = bounds
        panel.backdropView.frame = bounds
        container.addSubview(panel.fallbackBlur)
        container.addSubview(panel.backdropView)
        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.backdropView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: panel.backdropView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: panel.backdropView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: panel.backdropView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: panel.backdropView.bottomAnchor)
        ])
        panel.contentView = container
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

struct DesktopBackdrop {
    var full: NSImage
    var strip: NSImage
    var stripPointHeight: CGFloat
}

enum MenuBarCoverImage {
    private static var cacheKey: String?
    private static var cache: DesktopBackdrop?

    /// One blurred desktop picture. The grid shows all of it. The strip shows
    /// its top rows, at the same scale, so the two meet on a shared pixel row.
    static func backdrop(on screen: NSScreen) -> DesktopBackdrop? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let barPoints = MenuBarCoverPanel.barPoints(on: screen)
        let geometry = BackdropGeometry.make(
            screenWidth: Double(screen.frame.width),
            screenHeight: Double(screen.frame.height),
            scale: Double(screen.backingScaleFactor),
            barPoints: Double(barPoints)
        )
        let key = "\(url.path)|\(geometry.pixelWidth)x\(geometry.pixelHeight)|\(geometry.stripPixelHeight)"
        if key == cacheKey, let cache { return cache }
        guard let rendered = render(url: url, screen: screen.frame.size, geometry: geometry) else { return nil }
        cacheKey = key
        cache = rendered
        return rendered
    }

    private static func render(url: URL, screen: NSSize, geometry: BackdropGeometry) -> DesktopBackdrop? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        var proposed = NSRect(origin: .zero, size: source.size)
        guard let wallpaper = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let pixelW = CGFloat(geometry.pixelWidth)
        let pixelH = CGFloat(geometry.pixelHeight)
        let srcW = CGFloat(wallpaper.width)
        let srcH = CGFloat(wallpaper.height)
        let fit = max(pixelW / srcW, pixelH / srcH)
        let placed = CIImage(cgImage: wallpaper)
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(
                translationX: (pixelW - srcW * fit) / 2,
                y: (pixelH - srcH * fit) / 2
            ))
        let extent = CGRect(x: 0, y: 0, width: pixelW, height: pixelH)
        // Radius is in the picture's pixels. 52 points keeps the wallpaper's
        // vertical color (the sky band) instead of flattening it to one grey.
        let scale = pixelH / max(screen.height, 1)
        let radius = 52 * Double(scale)
        let blurred = placed.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        guard let fullImage = CIContext().createCGImage(blurred, from: extent) else { return nil }
        let stripPixels = geometry.stripPixelHeight
        guard let stripImage = fullImage.cropping(to: CGRect(
            x: 0,
            y: fullImage.height - stripPixels,
            width: fullImage.width,
            height: stripPixels
        )) else { return nil }
        let stripPoints = CGFloat(geometry.stripPointHeight)
        return DesktopBackdrop(
            full: NSImage(cgImage: fullImage, size: screen),
            strip: NSImage(cgImage: stripImage, size: NSSize(width: screen.width, height: stripPoints)),
            stripPointHeight: stripPoints
        )
    }
}

enum MenuBarPreference {
    /// Desktop & Dock "Automatically hide and show the menu bar" on this OS.
    /// Read only. A revealed bar still occupies `visibleFrame`, so the inset alone
    /// cannot tell a temporary reveal from a menu bar that is always visible.
    static var userAutoHidesMenuBar: Bool {
        guard let value = UserDefaults.standard.persistentDomain(forName: "com.apple.WindowManager")?["AutoHide"] else {
            return false
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
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
