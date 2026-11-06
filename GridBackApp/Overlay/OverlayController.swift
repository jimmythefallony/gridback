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
        guard menuBarSuppressed, let panel, panel.isVisible else {
            menuBarCover?.orderOut(nil)
            return
        }
        let cover = menuBarCover ?? MenuBarCoverPanel(screen: screen)
        menuBarCover = cover
        guard let snapshot = MenuBarCoverImage.strip(on: screen) else { return }
        cover.show(snapshot: snapshot, on: screen)
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

enum MenuBarCoverImage {
    private static var cacheKey: String?
    private static var cache: NSImage?

    /// The grid blurs the desktop. This strip uses that same picture, heavily
    /// softened and lifted the way the full-screen material does, then keeps
    /// only the top band. A material on the cover would blur the menu bar.
    static func strip(on screen: NSScreen) -> NSImage? {
        let height = MenuBarCoverPanel.frame(on: screen).height
        guard height > 1, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let key = "\(url.path)|\(Int(screen.frame.width))x\(Int(screen.frame.height))|\(Int(height))"
        if key == cacheKey, let cache { return cache }
        guard let image = render(url: url, screen: screen.frame.size, scale: screen.backingScaleFactor, stripHeight: height) else { return nil }
        cacheKey = key
        cache = image
        return image
    }

    private static func render(url: URL, screen: NSSize, scale: CGFloat, stripHeight: CGFloat) -> NSImage? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        var proposed = NSRect(origin: .zero, size: source.size)
        guard let wallpaper = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let pixelW = max(1, Int((screen.width * scale).rounded()))
        let pixelH = max(1, Int((screen.height * scale).rounded()))
        let srcW = CGFloat(wallpaper.width)
        let srcH = CGFloat(wallpaper.height)
        let fit = max(CGFloat(pixelW) / srcW, CGFloat(pixelH) / srcH)
        let placed = CIImage(cgImage: wallpaper)
            .transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            .transformed(by: CGAffineTransform(
                translationX: (CGFloat(pixelW) - srcW * fit) / 2,
                y: (CGFloat(pixelH) - srcH * fit) / 2
            ))
        let extent = CGRect(x: 0, y: 0, width: pixelW, height: pixelH)
        let radius = Double(max(screen.width, screen.height)) * 0.12
        let blurred = placed.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        let context = CIContext()
        guard let blurredImage = context.createCGImage(blurred, from: extent) else { return nil }
        let average = averageColor(blurredImage)
        let lifted = (
            r: min(255.0, average.r * 0.96),
            g: min(255.0, average.g * 0.55 + 78),
            b: min(255.0, average.b * 0.45 + 100)
        )
        guard let strip = blendTop(
            blurredImage,
            lifted: lifted,
            localWeight: 0.12,
            pixelHeight: max(1, Int((stripHeight * scale).rounded()))
        ) else { return nil }
        return NSImage(cgImage: strip, size: NSSize(width: screen.width, height: stripHeight))
    }

    private static func averageColor(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
        let sample = 24
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: sample,
            height: sample,
            bitsPerComponent: 8,
            bytesPerRow: sample * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sample, height: sample))
        guard let data = ctx.data else { return (128, 128, 128) }
        let bytes = data.bindMemory(to: UInt8.self, capacity: sample * sample * 4)
        var r = 0.0, g = 0.0, b = 0.0
        let count = sample * sample
        for i in 0..<count {
            r += Double(bytes[i * 4])
            g += Double(bytes[i * 4 + 1])
            b += Double(bytes[i * 4 + 2])
        }
        return (r / Double(count), g / Double(count), b / Double(count))
    }

    private static func blendTop(
        _ image: CGImage,
        lifted: (r: Double, g: Double, b: Double),
        localWeight: Double,
        pixelHeight: Int
    ) -> CGImage? {
        let width = image.width
        let height = min(pixelHeight, image.height)
        // CGImage's crop rect origin is the lower left. The menu bar is the top.
        let crop = image.cropping(to: CGRect(x: 0, y: image.height - height, width: width, height: height))
        guard let crop else { return nil }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let ctx, let dest = ctx.data else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        let out = dest.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let keep = localWeight
        let wash = 1 - localWeight
        for i in 0..<(width * height) {
            let d = i * 4
            out[d] = UInt8(min(255, Double(out[d]) * keep + lifted.r * wash))
            out[d + 1] = UInt8(min(255, Double(out[d + 1]) * keep + lifted.g * wash))
            out[d + 2] = UInt8(min(255, Double(out[d + 2]) * keep + lifted.b * wash))
            out[d + 3] = 255
        }
        return ctx.makeImage()
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
