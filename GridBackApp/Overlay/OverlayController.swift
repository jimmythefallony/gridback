import Accelerate
import AppKit
import GridBackCore
import ImageIO
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
    /// True from show until hide, including the moment before the windows are ordered front.
    private var wantsGrid = false
    /// Wallpaper identity the visible grid is waiting on. A finished render for another key is dropped.
    private var pictureKey: String?
    /// Wallpaper identity prepared for the next open, including while the grid is closed.
    private var preparedKey: String?
    private var inflightPictureKey: String?
    /// Last decision written to the log, so one open records one line.
    private var loggedDecision = ""
    private var loggedGeneration = -1
    /// System appearance last used for the blur. The grid window's own appearance is not this.
    private var lastSystemAppearance: WallpaperAppearance?
    private var appearanceObservation: NSKeyValueObservation?
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
        watchSystemAppearance()
        prewarmPicture()
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
        wantsGrid = true
        showGeneration += 1
        let generation = showGeneration
        let panel = self.panel ?? makePanel(on: screen, model: model)
        self.panel = panel
        let backdrop = self.dockBackdrop ?? DockBackdropPanel(screen: screen)
        self.dockBackdrop = backdrop
        // The window already stops at the Dock and covers the menu bar, so the
        // icon layout uses the window itself and is not inset a second time.
        // Read the Dock band before activation. Activating can reveal the menu
        // bar and change the top inset; the Dock edge does not depend on that.
        let occlusion = DockClearanceReader.current(on: screen).occlusion
        layoutFrames(panel: panel, backdrop: backdrop, on: screen, occlusion: occlusion)
        model.updateScreenReserve(.none)
        // The system launcher can open with us, or already be underneath.
        // Close it before we take the keyboard, and only once: the Dock
        // notification toggles, so a second send would open it again.
        didDismissSystemLauncher = false
        dismissSystemLauncherIfNeeded()
        installEscapeMonitor()
        startDockWatch()
        ensurePicture(generation: generation, on: screen)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.showGeneration == generation, self.wantsGrid else { return }
            self.claimKeyboard()
            if let screen = PrimaryDisplay.screen() {
                self.relayout(on: screen)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.showGeneration == generation, self.wantsGrid else { return }
            self.dismissSystemLauncherIfNeeded()
            self.claimKeyboard()
            if let screen = PrimaryDisplay.screen() {
                self.relayout(on: screen)
            }
        }
    }

    func hide() {
        wantsGrid = false
        removeEscapeMonitor()
        // If the system launcher is still underneath, close it with us so a
        // background click does not dismiss into Launchpad.
        dismissSystemLauncherIfNeeded()
        showGeneration += 1
        pictureKey = nil
        inflightPictureKey = nil
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
        guard wantsGrid, let screen = PrimaryDisplay.screen() else { return }
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
        guard wantsGrid, let model else { return }
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
                guard let self, self.wantsGrid else { return }
                if self.model?.heldDrag.isActive == true {
                    _ = self.model?.handleKeyDown(keyCode: 53, characters: "", modifiers: [])
                    return
                }
                self.model?.hideOverlay()
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
        guard wantsGrid, let screen = PrimaryDisplay.screen() else { return }
        relayout(on: screen)
    }

    private func relayout(on screen: NSScreen) {
        guard let panel, let model else { return }
        let backdrop = dockBackdrop ?? DockBackdropPanel(screen: screen)
        dockBackdrop = backdrop
        let occlusion = DockClearanceReader.current(on: screen).occlusion
        layoutFrames(panel: panel, backdrop: backdrop, on: screen, occlusion: occlusion)
        model.updateScreenReserve(.none)
        panel.level = OverlayPanel.gridLevel
        backdrop.level = DockBackdropPanel.backdropLevel
        ensurePicture(generation: showGeneration, on: screen)
    }

    private func layoutFrames(panel: OverlayPanel, backdrop: DockBackdropPanel, on screen: NSScreen, occlusion: DockOcclusion) {
        let screenFrame = screen.frame
        let frames = GridOverlayFrames.make(
            screenX: Double(screenFrame.origin.x),
            screenY: Double(screenFrame.origin.y),
            screenWidth: Double(screenFrame.size.width),
            screenHeight: Double(screenFrame.size.height),
            occlusion: occlusion
        )
        panel.setFrame(
            NSRect(x: frames.grid.x, y: frames.grid.y, width: frames.grid.width, height: frames.grid.height),
            display: false
        )
        backdrop.setFrame(
            NSRect(x: frames.backdrop.x, y: frames.backdrop.y, width: frames.backdrop.width, height: frames.backdrop.height),
            display: false
        )
        appliedOcclusion = occlusion
    }

    /// The grid window is fixed to dark Aqua, so its appearance is not the system's.
    /// Light and Dark wallpapers follow NSApp. A change pre-warms the other frame.
    private func watchSystemAppearance() {
        guard appearanceObservation == nil else { return }
        lastSystemAppearance = DesktopPicture.systemAppearance()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.systemAppearanceDidChange()
            }
        }
    }

    private func systemAppearanceDidChange() {
        let appearance = DesktopPicture.systemAppearance()
        guard appearance != lastSystemAppearance else { return }
        lastSystemAppearance = appearance
        if wantsGrid, let screen = PrimaryDisplay.screen() {
            ensurePicture(generation: showGeneration, on: screen)
        } else {
            prewarmPicture()
        }
    }

    /// Prepares the blur before the grid opens. Opening the grid already re-reads
    /// the wallpaper, so this runs at launch and when Light or Dark changes.
    private func prewarmPicture() {
        guard !wantsGrid, let screen = PrimaryDisplay.screen() else { return }
        let job = DesktopPicture.job(on: screen)
        notePicture(job)
        preparedKey = job.cacheKey
        guard !job.prefersPlainBlur, DesktopPicture.cached(job.cacheKey) == nil else { return }
        startPictureRender(job, generation: showGeneration)
    }

    /// Shows the shared blurred picture. A cached picture is applied immediately.
    /// A miss is rendered off the main thread, and the windows stay hidden until it arrives
    /// so the sharp wallpaper never flashes.
    private func ensurePicture(generation: Int, on screen: NSScreen) {
        let job = DesktopPicture.job(on: screen)
        notePicture(job)
        pictureKey = job.cacheKey
        preparedKey = job.cacheKey
        if job.prefersPlainBlur {
            showFallbackBlur()
            revealGrid()
            return
        }
        if let image = DesktopPicture.cached(job.cacheKey) {
            applyPicture(image, job: job)
            revealGrid()
            return
        }
        startPictureRender(job, generation: generation)
    }

    private func notePicture(_ job: DesktopPictureJob) {
        let file = WallpaperLogName.fileName(path: job.url?.path ?? job.logPath)
        let line = "kind=\(job.kind.rawValue) appearance=\(job.appearance.rawValue) reportedDefault=\(job.reportedSystemDefault) reason=\(job.reason.rawValue) file=\(file)"
        guard showGeneration != loggedGeneration || line != loggedDecision else { return }
        loggedGeneration = showGeneration
        loggedDecision = line
        log.info("DesktopPicture \(line, privacy: .public)")
    }

    private func startPictureRender(_ job: DesktopPictureJob, generation: Int) {
        let key = job.cacheKey
        guard inflightPictureKey != key else { return }
        inflightPictureKey = key
        log.info("DesktopPicture schedule main=\(Thread.isMainThread, privacy: .public)")
        OffMainWork.start {
            let onMain = Thread.isMainThread
            let qos = Int(qos_class_self().rawValue)
            let started = DispatchTime.now().uptimeNanoseconds
            let image = DesktopPicture.render(job)
            let milliseconds = Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
            return (onMain, qos, milliseconds, image)
        } apply: { [weak self] result in
            guard let self else { return }
            if self.inflightPictureKey == key {
                self.inflightPictureKey = nil
            }
            let (renderedOnMain, qos, milliseconds, cgImage) = result
            self.log.info("DesktopPicture render main=\(renderedOnMain, privacy: .public) qos=\(qos, privacy: .public) ms=\(milliseconds, privacy: .public) applyMain=\(Thread.isMainThread, privacy: .public)")
            let image = cgImage.map { NSImage(cgImage: $0, size: job.pointSize) }
            if let image, WallpaperPictureStore.shouldKeep(
                hasPicture: true,
                completedCacheKey: key,
                currentCacheKey: self.preparedKey ?? ""
            ) {
                DesktopPicture.store(image, key: key)
            }
            let applyGeneration = self.pictureKey == key ? self.showGeneration : generation
            self.presentWallpaper(
                hasPicture: image != nil,
                image: image,
                job: job,
                generation: applyGeneration,
                cacheKey: key
            )
        }
    }

    /// Opens the grid with the picture, or with the plain blur when there is none.
    /// A failure is not stored, so the next open tries the wallpaper again.
    private func presentWallpaper(
        hasPicture: Bool,
        image: NSImage?,
        job: DesktopPictureJob?,
        generation: Int,
        cacheKey: String
    ) {
        switch WallpaperBackdropChoice.choose(
            hasPicture: hasPicture,
            completedGeneration: generation,
            completedCacheKey: cacheKey,
            currentGeneration: showGeneration,
            currentCacheKey: pictureKey ?? "",
            stillWanted: wantsGrid
        ) {
        case .ignore:
            log.info("DesktopPicture drop stale generation=\(generation, privacy: .public)")
        case .plainBlur:
            log.error("DesktopPicture unavailable; opening with the plain blur")
            showFallbackBlur()
            revealGrid()
        case .picture:
            guard let image, let job else { return }
            DesktopPicture.store(image, key: cacheKey)
            applyPicture(image, job: job)
            revealGrid()
        }
    }

    private func showFallbackBlur() {
        guard let panel, let backdrop = dockBackdrop else { return }
        BackdropSurface.show(
            image: nil,
            placement: panel.contentView?.bounds ?? .zero,
            imageView: panel.backdropView,
            fallback: panel.fallbackBlur,
            window: panel
        )
        BackdropSurface.show(
            image: nil,
            placement: backdrop.contentView?.bounds ?? .zero,
            imageView: backdrop.backdropView,
            fallback: backdrop.fallbackBlur,
            window: backdrop
        )
    }

    private func applyPicture(_ image: NSImage, job: DesktopPictureJob) {
        guard let panel, let backdrop = dockBackdrop else { return }
        let screenRect = PlacedRect(x: job.screenX, y: job.screenY, width: job.screenWidth, height: job.screenHeight)
        let gridRect = PlacedRect(x: panel.frame.minX, y: panel.frame.minY, width: panel.frame.width, height: panel.frame.height)
        let backdropRect = PlacedRect(x: backdrop.frame.minX, y: backdrop.frame.minY, width: backdrop.frame.width, height: backdrop.frame.height)
        let gridPlacement = BackdropImagePlacement.inWindow(screen: screenRect, window: gridRect)
        let fullPlacement = BackdropImagePlacement.inWindow(screen: screenRect, window: backdropRect)
        BackdropSurface.show(
            image: image,
            placement: NSRect(x: gridPlacement.x, y: gridPlacement.y, width: gridPlacement.width, height: gridPlacement.height),
            imageView: panel.backdropView,
            fallback: panel.fallbackBlur,
            window: panel
        )
        BackdropSurface.show(
            image: image,
            placement: NSRect(x: fullPlacement.x, y: fullPlacement.y, width: fullPlacement.width, height: fullPlacement.height),
            imageView: backdrop.backdropView,
            fallback: backdrop.fallbackBlur,
            window: backdrop
        )
    }

    private func revealGrid() {
        guard wantsGrid, let panel, let backdrop = dockBackdrop else { return }
        panel.level = OverlayPanel.gridLevel
        backdrop.level = DockBackdropPanel.backdropLevel
        guard !panel.isVisible else { return }
        panel.alphaValue = 1
        backdrop.alphaValue = 1
        NSApp.unhide(nil)
        backdrop.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.level = OverlayPanel.gridLevel
        backdrop.level = DockBackdropPanel.backdropLevel
        claimKeyboard()
        if let screen = PrimaryDisplay.screen() {
            logDockBand(panel: panel, backdrop: backdrop, on: screen)
        }
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

struct DesktopPictureJob {
    var cacheKey: String
    var url: URL?
    var imageIndex: Int
    var kind: WallpaperKind
    var appearance: WallpaperAppearance
    var reportedSystemDefault: Bool
    var reason: WallpaperDecisionReason
    /// Path used only to name the file in the log. Not a picture to decode.
    var logPath: String?
    var solidColor: WallpaperSolidColor?
    var pointSize: NSSize
    var pixelWidth: Int
    var pixelHeight: Int
    var screenX: Double
    var screenY: Double
    var screenWidth: Double
    var screenHeight: Double

    var prefersPlainBlur: Bool { url == nil && solidColor == nil }
}

enum DesktopPicture {
    private static var cacheKey: String?
    private static var cache: NSImage?
    private static let signposter = OSSignposter(
        subsystem: "com.jimmythefallony.GridBack",
        category: .pointsOfInterest
    )

    static func systemAppearance() -> WallpaperAppearance {
        appearance(matching: NSApp.effectiveAppearance)
    }

    static func appearance(matching appearance: NSAppearance) -> WallpaperAppearance {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    /// The blur for the wallpaper on this screen. A moving or time-of-day wallpaper
    /// has no single frame, so the job asks for the plain blur instead.
    static func job(on screen: NSScreen) -> DesktopPictureJob {
        let appearance = systemAppearance()
        let workspaceURL = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL
        let workspacePath = workspaceURL?.path
        let placeholder = workspacePath.map(WallpaperReportedImage.isSystemDefault) ?? false
        var configured = WallpaperStoreReader.choice(for: screen)
        if let name = configured?.pictureName,
           configured?.role != .solidColor,
           configured?.role != .aerial,
           !hasRealFile(configured),
           let resolved = WallpaperPictureLocator.existingPicture(named: name) {
            configured = WallpaperConfiguredChoice(
                role: .file(path: resolved),
                color: configured?.color,
                pictureName: name,
                lastSet: configured?.lastSet ?? 0
            )
        }
        let selection = WallpaperSelectionResolver.select(configured: configured, workspacePath: workspacePath)
        let optionsFill = solidColor(on: screen)
        var hints = WallpaperMetadataHints.none
        var imageCount = 0
        var pixelWidth = 0
        var pixelHeight = 0
        var fileIsDirectory = false
        var sampled: WallpaperSolidColor?
        if case .file(let path) = selection {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue {
                fileIsDirectory = true
            } else {
                let read = WallpaperFileMetadata.read(at: URL(fileURLWithPath: path))
                hints = read.hints
                imageCount = read.imageCount
                pixelWidth = read.pixelWidth
                pixelHeight = read.pixelHeight
                if WallpaperImageExtent.isTinySolidCandidate(pixelWidth: pixelWidth, pixelHeight: pixelHeight) {
                    sampled = WallpaperFileMetadata.averageColor(at: URL(fileURLWithPath: path))
                }
            }
        }
        let tiny = WallpaperImageExtent.isTinySolidCandidate(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        let substantialPicture = imageCount > 0 && !fileIsDirectory && !tiny
        let knownColor = resolvedColor(
            sampled: sampled,
            stored: configured?.color,
            options: optionsFill,
            aerial: configured?.role == .aerial,
            substantialPicture: substantialPicture
        )
        let plainReason = plainDecisionReason(configured: configured, placeholder: placeholder)
        let plan = WallpaperBackdropPlanner.plan(
            selection: selection,
            hints: hints,
            imageCount: imageCount,
            appearance: appearance,
            fileIsDirectory: fileIsDirectory,
            solidFillAvailable: knownColor != nil,
            knownColor: knownColor,
            imageIsTiny: tiny,
            plainReason: plainReason
        )
        let scale = max(screen.backingScaleFactor, 1)
        let pixelW = max(1, Int((screen.frame.width * scale).rounded()))
        let pixelH = max(1, Int((screen.frame.height * scale).rounded()))
        let url: URL?
        let imageIndex: Int
        let color: WallpaperSolidColor?
        let token: String
        let logPath: String?
        switch plan {
        case .picture(let path, let index, _, _):
            url = URL(fileURLWithPath: path)
            imageIndex = index
            color = nil
            token = path
            logPath = path
        case .solidColor:
            url = nil
            imageIndex = 0
            color = knownColor ?? optionsFill
            token = colorToken(color)
            logPath = selectionPath(selection)
        case .plainBlur:
            url = nil
            imageIndex = 0
            color = nil
            token = "plain"
            logPath = selectionPath(selection)
        }
        return DesktopPictureJob(
            cacheKey: WallpaperCacheIdentity.key(
                token: token,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                appearance: appearance,
                kind: plan.kind,
                imageIndex: url == nil ? nil : imageIndex
            ),
            url: url,
            imageIndex: imageIndex,
            kind: plan.kind,
            appearance: appearance,
            reportedSystemDefault: placeholder,
            reason: plan.reason,
            logPath: logPath,
            solidColor: color,
            pointSize: screen.frame.size,
            pixelWidth: pixelW,
            pixelHeight: pixelH,
            screenX: Double(screen.frame.origin.x),
            screenY: Double(screen.frame.origin.y),
            screenWidth: Double(screen.frame.size.width),
            screenHeight: Double(screen.frame.size.height)
        )
    }

    private static func resolvedColor(
        sampled: WallpaperSolidColor?,
        stored: WallpaperSolidColor?,
        options: WallpaperSolidColor?,
        aerial: Bool,
        substantialPicture: Bool
    ) -> WallpaperSolidColor? {
        if let sampled { return sampled }
        if aerial || substantialPicture { return nil }
        return stored ?? options
    }

    private static func hasRealFile(_ choice: WallpaperConfiguredChoice?) -> Bool {
        guard let choice, case .file(let path) = choice.role else { return false }
        return !WallpaperReportedImage.isSystemDefault(path)
    }

    private static func selectionPath(_ selection: WallpaperSelection) -> String? {
        if case .file(let path) = selection { return path }
        return nil
    }

    private static func plainDecisionReason(
        configured: WallpaperConfiguredChoice?,
        placeholder: Bool
    ) -> WallpaperDecisionReason {
        if configured?.role == .aerial { return .aerial }
        if placeholder { return .placeholderUnidentified }
        return .noPicture
    }

    private static func colorToken(_ color: WallpaperSolidColor?) -> String {
        guard let color else { return "color" }
        return String(
            format: "color:%.4f,%.4f,%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            color.red,
            color.green,
            color.blue
        )
    }

    private static func solidColor(on screen: NSScreen) -> WallpaperSolidColor? {
        guard let options = NSWorkspace.shared.desktopImageOptions(for: screen),
              let color = options[.fillColor] as? NSColor,
              let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) else { return nil }
        func unit(_ value: CGFloat) -> Double { Double(min(max(value, 0), 1)) }
        return WallpaperSolidColor(red: unit(rgb.redComponent), green: unit(rgb.greenComponent), blue: unit(rgb.blueComponent))
    }

    static func cached(_ key: String) -> NSImage? {
        key == cacheKey ? cache : nil
    }

    static func store(_ image: NSImage, key: String) {
        cacheKey = key
        cache = image
    }

    /// Decodes a small thumbnail before anything draws it. ImageIO otherwise waits
    /// until the draw to decode the full image.
    private static func decodedThumbnail(at url: URL, index: Int, maxPixelSize: Int) -> CGImage? {
        guard index >= 0 else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptions as CFDictionary)
    }

    /// Blurs the desktop picture on the calling thread.
    /// The picture is decoded up front at a quarter of the screen, so drawing it does not
    /// decode a full-size image. The blur radius uses that same scale. Core Image is not used.
    static func render(_ job: DesktopPictureJob) -> CGImage? {
        let interval = signposter.beginInterval("WallpaperRender")
        defer { signposter.endInterval("WallpaperRender", interval) }
        let plan = WallpaperRenderSize.make(
            pixelWidth: job.pixelWidth,
            pixelHeight: job.pixelHeight,
            pointHeight: Double(job.pointSize.height)
        )
        let width = plan.width
        let height = plan.height
        guard width > 0, height > 0 else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let pixels = context.data else { return nil }
        context.interpolationQuality = .medium
        if let color = job.solidColor {
            context.setFillColor(CGColor(
                srgbRed: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        } else if let url = job.url {
            guard let wallpaper = decodedThumbnail(at: url, index: job.imageIndex, maxPixelSize: plan.maxPixelSize) else {
                return nil
            }
            let srcW = CGFloat(wallpaper.width)
            let srcH = CGFloat(wallpaper.height)
            guard srcW > 0, srcH > 0 else { return nil }
            let pixelW = CGFloat(width)
            let pixelH = CGFloat(height)
            let fit = max(pixelW / srcW, pixelH / srcH)
            let drawnW = srcW * fit
            let drawnH = srcH * fit
            context.draw(
                wallpaper,
                in: CGRect(x: (pixelW - drawnW) / 2, y: (pixelH - drawnH) / 2, width: drawnW, height: drawnH)
            )
        } else {
            return nil
        }
        var sourceBuffer = vImage_Buffer(
            data: pixels,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
        )
        var scratch = vImage_Buffer()
        let allocated = vImageBuffer_Init(
            &scratch,
            vImagePixelCount(height),
            vImagePixelCount(width),
            32,
            vImage_Flags(kvImageNoFlags)
        )
        guard allocated == kvImageNoError, scratch.data != nil else { return nil }
        defer { free(scratch.data) }
        let sigma = plan.sigma
        var resultInScratch = false
        let kernelLimit = min(width, height)
        for kernel in GaussianBoxKernel.sizes(sigma: sigma, passes: 3) {
            let fitted = kernel <= kernelLimit ? kernel : (kernelLimit % 2 == 1 ? kernelLimit : max(kernelLimit - 1, 1))
            let size = UInt32(fitted)
            let error: vImage_Error
            if resultInScratch {
                error = vImageBoxConvolve_ARGB8888(
                    &scratch, &sourceBuffer, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend)
                )
            } else {
                error = vImageBoxConvolve_ARGB8888(
                    &sourceBuffer, &scratch, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend)
                )
            }
            guard error == kvImageNoError else { return nil }
            resultInScratch.toggle()
        }
        if resultInScratch {
            guard vImageCopyBuffer(&scratch, &sourceBuffer, 4, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
                return nil
            }
        }
        return context.makeImage()
    }
}

/// The wallpaper the system recorded for this display. Missing or unreadable means
/// the workspace image URL is the only picture available.
enum WallpaperPictureLocator {
    static func existingPicture(named name: String) -> String? {
        for path in WallpaperSystemPicture.candidatePaths(name: name) {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}

enum WallpaperStoreReader {
    static func choice(for screen: NSScreen) -> WallpaperConfiguredChoice? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: url),
              let store = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return WallpaperStoreIndex.choice(in: store, displayUUID: displayUUID(of: screen))
    }

    private static func displayUUID(of screen: NSScreen) -> String? {
        guard let displayID = PrimaryDisplay.displayID(of: screen),
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// `apr`, `h24`, and `solar` on a HEIC file. The tag is only a hint: the value is
/// a property list in base 64, and a tag with no usable value still counts as present.
enum WallpaperFileMetadata {
    static func read(at url: URL) -> (hints: WallpaperMetadataHints, imageCount: Int, pixelWidth: Int, pixelHeight: Int) {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return (.none, 0, 0, 0)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return (.none, 0, 0, 0) }
        let size = pixelSize(of: source)
        var apr: String?
        var day: String?
        var solar: String?
        let primary = CGImageSourceGetPrimaryImageIndex(source)
        for index in [0, primary] where index >= 0 && index < count {
            guard let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil) else { continue }
            apr = apr ?? tag("apple_desktop:apr", in: metadata)
            day = day ?? tag("apple_desktop:h24", in: metadata)
            solar = solar ?? tag("apple_desktop:solar", in: metadata)
        }
        return (WallpaperMetadataDecoder.hints(aprBase64: apr, h24Base64: day, solarBase64: solar), count, size.width, size.height)
    }

    /// One pixel from a very small picture. Large files are not decoded here.
    static func averageColor(at url: URL) -> WallpaperSolidColor? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return WallpaperSolidColor(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int) {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return (0, 0)
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        return (width, height)
    }

    private static func tag(_ name: String, in metadata: CGImageMetadata) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, name as CFString) else { return nil }
        if let text = CGImageMetadataTagCopyValue(tag) as? String { return text }
        return ""
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
