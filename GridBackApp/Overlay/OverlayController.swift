import AppKit
import CoreImage
import GridBackCore
import os
import SwiftUI

/// Owns the single overlay panel and moves it onto the primary display.
/// Use this on the main thread.
final class OverlayController: NSObject {
    private var panel: OverlayPanel?
    private var dockBackdrop: DockBackdropPanel?
    private var model: GridBackModel?
    private var screenObserver: NSObjectProtocol?
    /// Bumps on each show so a delayed pass cannot reopen a grid that already closed.
    private var showGeneration = 0
    /// One dismiss per open. Toggling twice would show the system launcher again.
    private var didDismissSystemLauncher = false
    private var escapeMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var dockWatch: Timer?
    private var appliedOcclusion: DockOcclusion?
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
        let backdrop = self.dockBackdrop ?? DockBackdropPanel(screen: screen)
        self.dockBackdrop = backdrop
        // The window already stops at the Dock and covers the menu bar, so the
        // icon layout uses the window itself and is not inset a second time.
        // Read the Dock band before activation. Activating can reveal the menu
        // bar and change the top inset; the Dock edge does not depend on that.
        let occlusion = DockClearanceReader.current(on: screen).occlusion
        place(panel: panel, backdrop: backdrop, on: screen, occlusion: occlusion)
        model.updateScreenReserve(.none)
        showGeneration += 1
        let generation = showGeneration
        // The system launcher can open with us, or already be underneath.
        // Close it before we take the keyboard, and only once: the Dock
        // notification toggles, so a second send would open it again.
        didDismissSystemLauncher = false
        dismissSystemLauncherIfNeeded()
        panel.alphaValue = 1
        backdrop.alphaValue = 1
        NSApp.unhide(nil)
        backdrop.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        // AppKit can drop a panel's level while ordering it.
        panel.level = OverlayPanel.gridLevel
        backdrop.level = DockBackdropPanel.backdropLevel
        claimKeyboard()
        installEscapeMonitor()
        startDockWatch()
        logDockBand(panel: panel, backdrop: backdrop, on: screen)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.showGeneration == generation, self.panel?.isVisible == true else { return }
            self.claimKeyboard()
            if let screen = PrimaryDisplay.screen() {
                self.relayout(on: screen)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.showGeneration == generation, self.panel?.isVisible == true else { return }
            self.dismissSystemLauncherIfNeeded()
            self.claimKeyboard()
            if let screen = PrimaryDisplay.screen() {
                self.relayout(on: screen)
            }
        }
    }

    func hide() {
        removeEscapeMonitor()
        // If the system launcher is still underneath, close it with us so a
        // background click does not dismiss into Launchpad.
        dismissSystemLauncherIfNeeded()
        showGeneration += 1
        stopDockWatch()
        dockBackdrop?.orderOut(nil)
        panel?.orderOut(nil)
    }

    /// Dock preferences can land on disk after the Dock has already started magnifying.
    /// Keep looking while the grid is up so the band moves without a relaunch.
    private func startDockWatch() {
        stopDockWatch()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.refreshDockBandIfNeeded()
        }
        dockWatch = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopDockWatch() {
        dockWatch?.invalidate()
        dockWatch = nil
        appliedOcclusion = nil
    }

    private func refreshDockBandIfNeeded() {
        guard panel?.isVisible == true, let screen = PrimaryDisplay.screen() else { return }
        let occlusion = DockClearanceReader.current(on: screen).occlusion
        guard occlusion != appliedOcclusion else { return }
        relayout(on: screen)
        if let panel, let backdrop = dockBackdrop {
            logDockBand(panel: panel, backdrop: backdrop, on: screen)
        }
    }

    private func logDockBand(panel: OverlayPanel, backdrop: DockBackdropPanel, on screen: NSScreen) {
        let reading = DockClearanceReader.current(on: screen)
        let frame = panel.frame
        log.info("Dock band magnification=\(reading.magnifies, privacy: .public) largesize=\(reading.largeSize, privacy: .public) largesizeStored=\(reading.largeSizeWasStored, privacy: .public) tilesize=\(reading.tileSize, privacy: .public) autohide=\(reading.autoHides, privacy: .public) orientation=\(reading.orientation, privacy: .public) source=\(reading.source, privacy: .public) thickness=\(reading.occlusion.thickness, privacy: .public) edge=\(String(describing: reading.occlusion.edge), privacy: .public) frame=\(NSStringFromRect(frame), privacy: .public) level=\(panel.level.rawValue, privacy: .public) backdrop=\(NSStringFromRect(backdrop.frame), privacy: .public) backdropLevel=\(backdrop.level.rawValue, privacy: .public)")
    }

    private func claimKeyboard() {
        guard panel?.isVisible == true else { return }
        // Stay accessory for the whole lifetime so GridBack never appears in
        // the Dock or in Command-Tab. Presentation options are not changed.
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
        panel?.level = OverlayPanel.gridLevel
        dockBackdrop?.level = DockBackdropPanel.backdropLevel
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

    private func relayoutIfVisible() {
        guard panel?.isVisible == true, let screen = PrimaryDisplay.screen() else { return }
        relayout(on: screen)
    }

    private func relayout(on screen: NSScreen) {
        guard let panel, let model else { return }
        let backdrop = dockBackdrop ?? DockBackdropPanel(screen: screen)
        dockBackdrop = backdrop
        let occlusion = DockClearanceReader.current(on: screen).occlusion
        place(panel: panel, backdrop: backdrop, on: screen, occlusion: occlusion)
        model.updateScreenReserve(.none)
        panel.level = OverlayPanel.gridLevel
        backdrop.level = DockBackdropPanel.backdropLevel
    }

    private func place(panel: OverlayPanel, backdrop: DockBackdropPanel, on screen: NSScreen, occlusion: DockOcclusion) {
        let screenFrame = screen.frame
        let frames = GridOverlayFrames.make(
            screenX: Double(screenFrame.origin.x),
            screenY: Double(screenFrame.origin.y),
            screenWidth: Double(screenFrame.size.width),
            screenHeight: Double(screenFrame.size.height),
            occlusion: occlusion
        )
        let gridRect = NSRect(x: frames.grid.x, y: frames.grid.y, width: frames.grid.width, height: frames.grid.height)
        let backdropRect = NSRect(x: frames.backdrop.x, y: frames.backdrop.y, width: frames.backdrop.width, height: frames.backdrop.height)
        panel.setFrame(gridRect, display: false)
        backdrop.setFrame(backdropRect, display: false)
        let picture = DesktopPicture.image(on: screen)
        let gridPlacement = BackdropImagePlacement.inWindow(screen: frames.backdrop, window: frames.grid)
        let fullPlacement = BackdropImagePlacement.inWindow(screen: frames.backdrop, window: frames.backdrop)
        BackdropSurface.show(
            image: picture,
            placement: NSRect(x: gridPlacement.x, y: gridPlacement.y, width: gridPlacement.width, height: gridPlacement.height),
            imageView: panel.backdropView,
            fallback: panel.fallbackBlur,
            window: panel
        )
        BackdropSurface.show(
            image: picture,
            placement: NSRect(x: fullPlacement.x, y: fullPlacement.y, width: fullPlacement.width, height: fullPlacement.height),
            imageView: backdrop.backdropView,
            fallback: backdrop.fallbackBlur,
            window: backdrop
        )
        appliedOcclusion = occlusion
    }

    private func makePanel(on screen: NSScreen, model: GridBackModel) -> OverlayPanel {
        let panel = OverlayPanel(screen: screen)
        let hosting = NSHostingView(rootView: OverlayRootView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        guard let container = panel.contentView else { return panel }
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
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

enum DesktopPicture {
    private static var cacheKey: String?
    private static var cache: NSImage?

    /// One blurred desktop picture at the screen's pixel size. Both windows
    /// display this image; neither applies a material on top of it.
    static func image(on screen: NSScreen) -> NSImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let scale = max(screen.backingScaleFactor, 1)
        let pixelW = max(1, Int((screen.frame.width * scale).rounded()))
        let pixelH = max(1, Int((screen.frame.height * scale).rounded()))
        let key = "\(url.path)|\(pixelW)x\(pixelH)"
        if key == cacheKey, let cache { return cache }
        guard let rendered = render(url: url, pointSize: screen.frame.size, pixelWidth: pixelW, pixelHeight: pixelH) else { return nil }
        cacheKey = key
        cache = rendered
        return rendered
    }

    private static func render(url: URL, pointSize: NSSize, pixelWidth: Int, pixelHeight: Int) -> NSImage? {
        guard let source = NSImage(contentsOf: url) else { return nil }
        var proposed = NSRect(origin: .zero, size: source.size)
        guard let wallpaper = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let pixelW = CGFloat(pixelWidth)
        let pixelH = CGFloat(pixelHeight)
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
        let scale = pixelH / max(pointSize.height, 1)
        let radius = 52 * Double(scale)
        let blurred = placed.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        guard let fullImage = CIContext().createCGImage(blurred, from: extent) else { return nil }
        return NSImage(cgImage: fullImage, size: pointSize)
    }
}

struct DockReading: Equatable {
    var magnifies: Bool
    var largeSize: Double
    var largeSizeWasStored: Bool
    var tileSize: Double
    var autoHides: Bool
    var orientation: String
    var source: String
    var occlusion: DockOcclusion
}

enum DockClearanceReader {
    /// Reads Dock geometry from the plist and from cfprefsd. Does not write settings.
    /// A missing `largesize` with magnification on uses 128. Called on each open and
    /// while the grid is visible, because the Dock can magnify before the key is flushed.
    static func current(on screen: NSScreen) -> DockReading {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let file = readPlist()
        let cfMagnifies = flag(copy("magnification"))
        let fileMagnifies = flag(file?["magnification"])
        let magnifies = cfMagnifies || fileMagnifies
        let cfLarge = number(copy("largesize"))
        let fileLarge = number(file?["largesize"])
        let storedLarge = cfLarge ?? fileLarge
        let tile = number(copy("tilesize")) ?? number(file?["tilesize"]) ?? 64
        let autoHides = flag(copy("autohide")) || flag(file?["autohide"])
        let orientation = (copy("orientation") as? String) ?? (file?["orientation"] as? String) ?? "bottom"
        let edge: DockEdge
        switch orientation {
        case "left": edge = .left
        case "right": edge = .right
        default: edge = .bottom
        }
        let large = DockOcclusion.largeSize(stored: storedLarge, magnificationEnabled: magnifies)
        let source = "cf=\(cfMagnifies) file=\(fileMagnifies)"
        let occlusion = DockOcclusion.resolve(
            reserve: ScreenReserveReader.current(on: screen),
            autoHides: autoHides,
            autoHideEdge: edge,
            estimatedAutoHideThickness: DockOcclusion.autoHideThickness(tileSize: tile),
            magnificationOverflow: DockOcclusion.magnificationOverflow(enabled: magnifies, tileSize: tile, largeSize: large),
            scale: Double(screen.backingScaleFactor)
        )
        return DockReading(
            magnifies: magnifies,
            largeSize: large,
            largeSizeWasStored: storedLarge != nil,
            tileSize: tile,
            autoHides: autoHides,
            orientation: orientation,
            source: source,
            occlusion: occlusion
        )
    }

    private static func readPlist() -> [String: Any]? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.dock.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }

    private static func copy(_ key: String) -> Any? {
        CFPreferencesCopyValue(
            key as CFString,
            "com.apple.dock" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
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
