import Accelerate
import AppKit
@preconcurrency import AVFoundation
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
    /// Aerial grab still running. Closing the grid does not start a second one.
    private var aerialInFlightKey: String?
    /// A grab that produced no frame. Relayout does not retry it; the next open does.
    private var aerialFailedKey: String?
    private var loggedSolidColorNames = false
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
        // The hotkey already started the interval. Any other trigger starts here.
        GridOpenTrace.shared.showTriggerArrived()
        guard let model else {
            log.error("Show skipped: overlay has no model")
            GridOpenTrace.shared.abandonOpening()
            return
        }
        guard let screen = PrimaryDisplay.screen() else {
            log.error("Show skipped: no primary display")
            GridOpenTrace.shared.abandonOpening()
            return
        }
        wantsGrid = true
        showGeneration += 1
        let generation = showGeneration
        let createdPanel = self.panel == nil
        let panel = self.panel ?? makePanel(on: screen, model: model)
        self.panel = panel
        GridOpenTrace.shared.notePanel(created: createdPanel)
        let backdrop = self.dockBackdrop ?? DockBackdropPanel(screen: screen, ink: model.ink)
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
        GridOpenTrace.shared.gridClosed()
        wantsGrid = false
        removeEscapeMonitor()
        // If the system launcher is still underneath, close it with us so a
        // background click does not dismiss into Launchpad.
        dismissSystemLauncherIfNeeded()
        showGeneration += 1
        pictureKey = nil
        inflightPictureKey = nil
        aerialFailedKey = nil
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
        let backdrop = dockBackdrop ?? DockBackdropPanel(screen: screen, ink: model.ink)
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

    /// The grid window follows the ink, not the system appearance. Light and Dark
    /// wallpapers follow NSApp. A change pre-warms the other frame, and an open
    /// grid crossfades onto it.
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

    /// Prepares the blur while the grid is closed, including after a wallpaper folder is allowed.
    func preparePictureForNextOpen() {
        guard !wantsGrid else { return }
        prewarmPicture()
    }

    private func pictureJob(on screen: NSScreen) -> DesktopPictureJob {
        DesktopPicture.job(
            on: screen,
            askedLocations: model?.folderAsked ?? [],
            grantedLocations: model?.folderGranted ?? []
        )
    }

    /// Prepares the blur before the grid opens. Opening the grid already re-reads
    /// the wallpaper, so this runs at launch and when Light or Dark changes.
    /// An Aerial frame is grabbed here too, so a later open can use the cache.
    private func prewarmPicture() {
        guard !wantsGrid, let screen = PrimaryDisplay.screen() else { return }
        DesktopPicture.dropRefusedFallback()
        let job = pictureJob(on: screen)
        notePicture(job)
        preparedKey = job.cacheKey
        guard DesktopPicture.cached(job.cacheKey) == nil else { return }
        if job.aerialAssetID != nil {
            startAerialFrame(job, generation: showGeneration)
            return
        }
        startPictureRender(job, generation: showGeneration)
    }

    /// Shows the shared blurred picture. A cached picture is applied immediately.
    /// A photo miss is rendered off the main thread, and the windows stay hidden until it arrives
    /// so the sharp wallpaper never flashes.
    /// An Aerial miss shows the plain fallback immediately. The frame is grabbed
    /// off the main thread and fades in when it is ready. `show()` does not wait.
    private func ensurePicture(generation: Int, on screen: NSScreen) {
        let job = pictureJob(on: screen)
        notePicture(job)
        pictureKey = job.cacheKey
        preparedKey = job.cacheKey
        if let image = DesktopPicture.cached(job.cacheKey) {
            applyPicture(image, job: job)
            revealGrid()
            return
        }
        if job.aerialAssetID != nil {
            if panel?.isVisible != true {
                var holding = job
                holding.url = nil
                holding.aerialAssetID = nil
                holding.kind = .fallback
                holding.solidColor = WallpaperNeutralFill.color(for: job.appearance)
                showSharedFill(holding.solidColor ?? WallpaperNeutralFill.color(for: holding.appearance), job: holding)
                revealGrid()
            }
            startAerialFrame(job, generation: generation)
            return
        }
        startPictureRender(job, generation: generation)
    }

    private func notePicture(_ job: DesktopPictureJob) {
        let provider = job.provider.isEmpty ? "none" : job.provider
        let keys = WallpaperLogName.configKeys(job.configKeys)
        let colors = job.colorValueLog.isEmpty ? "none" : job.colorValueLog
        let line = "source=\(job.source.rawValue) provider=\(provider) configKeys=\(keys) kind=\(job.kind.rawValue) appearance=\(job.appearance.rawValue) reportedDefault=\(job.reportedSystemDefault) colorValues=\(colors)"
        guard showGeneration != loggedGeneration || line != loggedDecision else { return }
        loggedGeneration = showGeneration
        loggedDecision = line
        if !loggedSolidColorNames {
            loggedSolidColorNames = true
            let names = WallpaperSolidColors.normalizedNames().joined(separator: ",")
            log.info("DesktopPicture solidColorNames=\(names.isEmpty ? "none" : names, privacy: .public)")
        }
        log.info("DesktopPicture source=\(job.source.rawValue, privacy: .public) provider=\(provider, privacy: .public) configKeys=\(keys, privacy: .public) kind=\(job.kind.rawValue, privacy: .public) appearance=\(job.appearance.rawValue, privacy: .public) reportedDefault=\(job.reportedSystemDefault, privacy: .public) colorValues=\(colors, privacy: .public)")
        if job.provider == WallpaperStoreIndex.aerialsProvider {
            let recordLine = WallpaperAerialLog.recordLine(
                record: job.aerialRecord,
                provider: job.provider,
                keys: job.configKeys
            )
            log.info("DesktopPicture aerial \(recordLine, privacy: .public)")
        }
        if !job.urlLog.isEmpty {
            log.info("DesktopPicture \(job.urlLog, privacy: .public)")
        }
        if !job.matchLog.isEmpty {
            log.info("DesktopPicture \(job.matchLog, privacy: .public)")
        }
        if !job.structureLog.isEmpty {
            log.info("DesktopPicture structure=\(job.structureLog, privacy: .public)")
        }
        if let place = job.folderPlace, let decision = job.folderDecision {
            log.info("\(FolderAccessLog.line(place: place, decision: decision), privacy: .public)")
        }
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

    /// Grabs one Aerial frame off the main thread, blurs it, and keeps only that image.
    /// A miss leaves the fallback that `show()` already put up.
    private func startAerialFrame(_ job: DesktopPictureJob, generation: Int) {
        let key = job.cacheKey
        guard let url = job.url, url.isFileURL else { return }
        guard aerialInFlightKey != key, aerialFailedKey != key else { return }
        aerialInFlightKey = key
        inflightPictureKey = key
        log.info("DesktopPicture aerial schedule main=\(Thread.isMainThread, privacy: .public)")
        OffMainWork.start {
            let onMain = Thread.isMainThread
            let qos = Int(qos_class_self().rawValue)
            let started = DispatchTime.now().uptimeNanoseconds
            let maxPixel = WallpaperRenderSize.make(
                pixelWidth: job.pixelWidth,
                pixelHeight: job.pixelHeight,
                pointHeight: Double(job.pointSize.height)
            ).maxPixelSize
            let frame = AerialFrameGrabber.blockingFrame(fileURL: url, maxPixelSize: maxPixel)
            let image = frame.flatMap { DesktopPicture.render(job, frame: $0) }
            let milliseconds = Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
            return (onMain, qos, milliseconds, image)
        } apply: { [weak self] result in
            guard let self else { return }
            if self.inflightPictureKey == key {
                self.inflightPictureKey = nil
            }
            if self.aerialInFlightKey == key {
                self.aerialInFlightKey = nil
            }
            let (renderedOnMain, qos, milliseconds, cgImage) = result
            self.log.info("DesktopPicture aerial render main=\(renderedOnMain, privacy: .public) qos=\(qos, privacy: .public) ms=\(milliseconds, privacy: .public) applyMain=\(Thread.isMainThread, privacy: .public)")
            guard let cgImage else {
                self.aerialFailedKey = key
                return
            }
            let image = NSImage(cgImage: cgImage, size: job.pointSize)
            if WallpaperPictureStore.shouldKeep(
                hasPicture: true,
                completedCacheKey: key,
                currentCacheKey: self.preparedKey ?? ""
            ) {
                DesktopPicture.store(image, key: key)
            }
            let applyGeneration = self.pictureKey == key ? self.showGeneration : generation
            self.presentWallpaper(
                hasPicture: true,
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
            log.error("DesktopPicture unavailable; opening with the neutral fill")
            let fill = job?.solidColor ?? WallpaperNeutralFill.color(for: job?.appearance ?? .dark)
            showSharedFill(fill, job: job)
            revealGrid()
        case .picture:
            guard let image, let job else { return }
            DesktopPicture.store(image, key: cacheKey)
            applyPicture(image, job: job)
            revealGrid()
        }
    }

    /// One still image for both windows. A live behind-window blur would be sampled
    /// twice, so the grid and the Dock band would not match. Reduce Transparency
    /// stays sensible because this image is already flat or already blurred.
    private func showSharedFill(_ color: WallpaperSolidColor, job: DesktopPictureJob?) {
        guard let panel, let _ = dockBackdrop else { return }
        let width = job?.pixelWidth ?? 32
        let height = job?.pixelHeight ?? 32
        let pointSize = job?.pointSize ?? panel.frame.size
        guard let image = DesktopPicture.flatImage(color: color, pixelWidth: width, pixelHeight: height, pointSize: pointSize) else { return }
        let screen = job ?? DesktopPictureJob(
            cacheKey: "",
            url: nil,
            imageIndex: 0,
            kind: .fallback,
            appearance: .dark,
            reportedSystemDefault: false,
            source: .none,
            provider: "",
            configKeys: [],
            colorValueLog: "",
            solidColor: color,
            pointSize: pointSize,
            pixelWidth: width,
            pixelHeight: height,
            screenX: Double(panel.frame.minX),
            screenY: Double(panel.frame.minY),
            screenWidth: Double(panel.frame.width),
            screenHeight: Double(panel.frame.height),
            askPath: nil,
            askPlace: nil,
            askVolumeKind: .none,
            folderPlace: nil,
            folderDecision: nil
        )
        applyPicture(image, job: screen)
    }

    private func applyPicture(_ image: NSImage, job: DesktopPictureJob) {
        guard let panel, let backdrop = dockBackdrop, let model else { return }
        let fill = job.solidColor ?? WallpaperNeutralFill.color(for: job.appearance)
        let source = BackdropInkSource.resolve(
            hasPicture: job.url != nil,
            isSolidColor: job.kind == .solidColor,
            fill: fill
        )
        let ink = Ink.forBackdrop(source, previous: model.ink)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animate = panel.isVisible && !reduceMotion
        if ink != model.ink {
            log.info("Ink \(String(describing: ink), privacy: .public) kind=\(job.kind.rawValue, privacy: .public)")
        }
        var transaction = Transaction()
        if animate {
            transaction.animation = .easeInOut(duration: InkCrossfade.duration)
        } else {
            transaction.disablesAnimations = true
        }
        withTransaction(transaction) {
            model.setInk(ink)
        }
        panel.apply(ink: ink)
        backdrop.apply(ink: ink)
        let screenRect = PlacedRect(x: job.screenX, y: job.screenY, width: job.screenWidth, height: job.screenHeight)
        let gridRect = PlacedRect(x: panel.frame.minX, y: panel.frame.minY, width: panel.frame.width, height: panel.frame.height)
        let backdropRect = PlacedRect(x: backdrop.frame.minX, y: backdrop.frame.minY, width: backdrop.frame.width, height: backdrop.frame.height)
        let gridPlacement = BackdropImagePlacement.inWindow(screen: screenRect, window: gridRect)
        let fullPlacement = BackdropImagePlacement.inWindow(screen: screenRect, window: backdropRect)
        BackdropSurface.show(
            image: image,
            placement: NSRect(x: gridPlacement.x, y: gridPlacement.y, width: gridPlacement.width, height: gridPlacement.height),
            imageView: panel.backdropView,
            window: panel,
            crossfade: animate
        )
        BackdropSurface.show(
            image: image,
            placement: NSRect(x: fullPlacement.x, y: fullPlacement.y, width: fullPlacement.width, height: fullPlacement.height),
            imageView: backdrop.backdropView,
            window: backdrop,
            crossfade: animate
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
        GridOpenTrace.shared.panelOrderedFront()
    }

    private func makePanel(on screen: NSScreen, model: GridBackModel) -> OverlayPanel {
        let panel = OverlayPanel(screen: screen, ink: model.ink)
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
    var source: WallpaperSource
    var provider: String
    var configKeys: [String]
    var colorValueLog: String
    var urlLog: String = ""
    var matchLog: String = ""
    var structureLog: String = ""
    var solidColor: WallpaperSolidColor?
    /// Set when a local Aerial movie is ready to grab. The cache token is this id, not a path.
    var aerialAssetID: String?
    /// `Desktop` or `Linked` when the provider is Aerials.
    var aerialRecord: String = ""
    var pointSize: NSSize
    var pixelWidth: Int
    var pixelHeight: Int
    var screenX: Double
    var screenY: Double
    var screenWidth: Double
    var screenHeight: Double
    /// Set only when the explainer may be offered. The path is kept for the later read and is not logged.
    var askPath: String? = nil
    var askPlace: WallpaperPathPlace? = nil
    var askVolumeKind: FolderVolumeKind = .none
    /// The protected place this picture came from, when there is one. Logged by name only.
    var folderPlace: WallpaperPathPlace? = nil
    var folderDecision: FolderAccessDecision? = nil

    var prefersPlainBlur: Bool { url == nil && solidColor == nil }
}

/// One still from a local Aerial movie. A remote URL is refused before any asset is made.
/// The asset and the generator are released when the grab returns.
enum AerialFrameGrabber {
    static func blockingFrame(fileURL: URL, maxPixelSize: Int) -> CGImage? {
        guard isLocalMovie(fileURL) else { return nil }
        let gate = FrameGate()
        Task.detached(priority: .medium) {
            let image = await frame(fileURL: fileURL, maxPixelSize: maxPixelSize)
            gate.finish(image)
        }
        return gate.wait()
    }

    private static func frame(fileURL: URL, maxPixelSize: Int) async -> CGImage? {
        guard isLocalMovie(fileURL) else { return nil }
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let side = CGFloat(max(maxPixelSize, 1))
        generator.maximumSize = CGSize(width: side, height: side)
        let slack = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack
        do {
            let duration = try await asset.load(.duration)
            guard duration.isNumeric else { return nil }
            let seconds = duration.seconds * WallpaperAerialCatalogue.frameFraction
            guard seconds.isFinite, seconds >= 0 else { return nil }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let generated = try await generator.image(at: time)
            return generated.image
        } catch {
            return nil
        }
    }

    private static func isLocalMovie(_ url: URL) -> Bool {
        guard url.isFileURL, url.scheme?.lowercased() == "file" else { return false }
        if let host = url.host, !host.isEmpty, host.caseInsensitiveCompare("localhost") != .orderedSame {
            return false
        }
        return url.lastPathComponent.lowercased().hasSuffix(".mov")
    }

    private final class FrameGate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private var image: CGImage?
        func finish(_ image: CGImage?) {
            self.image = image
            semaphore.signal()
        }
        func wait() -> CGImage? {
            semaphore.wait()
            return image
        }
    }
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

    /// The blur for the wallpaper on this screen. A time-of-day photo has no single
    /// frame, so the job asks for the plain blur. A downloaded Aerial uses one
    /// frame of the local movie. A missing movie stays the plain blur.
    /// A sandboxed build cannot read the wallpaper store, and then only a plain
    /// photo URL is used.
    static func job(
        on screen: NSScreen,
        askedLocations: Set<WallpaperPathPlace> = [],
        grantedLocations: Set<WallpaperPathPlace> = []
    ) -> DesktopPictureJob {
        let appearance = systemAppearance()
        let workspacePath = NSWorkspace.shared.desktopImageURL(for: screen)?.path
        let stored = WallpaperStoreReader.load()
        var choice = stored.choice
        if choice?.solidColor == nil,
           let colorPath = choice?.solidColorImagePath,
           !WallpaperPathPlace.classify(colorPath).isProtected {
            choice?.solidColor = WallpaperFileMetadata.averageColor(at: URL(fileURLWithPath: colorPath))
        }
        if choice?.provider == WallpaperStoreIndex.colorProvider,
           choice?.solidColor == nil,
           let name = choice?.systemColorName,
           let file = WallpaperSolidColors.existingFile(matching: name) {
            choice?.solidColor = WallpaperFileMetadata.averageColor(at: URL(fileURLWithPath: file))
        }
        if choice?.solidColor == nil, let archived = choice?.archivedColor {
            choice?.solidColor = WallpaperArchivedColor.color(from: archived)
        }
        let access = WallpaperFileAccess.inspect(choice)
        if let usable = access.usablePath {
            choice?.imageFilePath = usable
        }
        choice?.locationBlocked = access.locationBlocked
        if access.locationBlocked || access.reason == "unreadable" {
            choice?.allowLegacy = false
        }
        var decision = WallpaperChoicePolicy.resolve(
            choice: choice,
            workspacePath: workspacePath,
            imageFileReadable: access.usablePath != nil,
            storeFileExists: access.storeFileExists
        )
        if case .imageFile(let path) = decision.use {
            if WallpaperFileAccess.look(path) == nil {
                decision = (source: decision.source, use: .plainBlur, kind: .fallback)
            } else if access.usablePath != path, let looked = WallpaperFileAccess.look(path), !looked.readable {
                decision = looked.exists
                    ? (source: decision.source, use: .plainBlur, kind: .unreadable)
                    : (source: decision.source, use: .plainBlur, kind: .fallback)
            }
        }
        let resolvedUseIsFile: Bool
        if case .imageFile = decision.use {
            resolvedUseIsFile = true
        } else {
            resolvedUseIsFile = false
        }
        let protected = FolderAskTargeting.protectedPicture(
            provider: choice?.provider,
            isFolder: choice?.isFolder ?? false,
            storePaths: choice.map { candidate in
                candidate.imageCandidates.isEmpty
                    ? (candidate.imageFilePath.map { [$0] } ?? [])
                    : candidate.imageCandidates
            } ?? [],
            workspacePath: workspacePath,
            resolvedUseIsFile: resolvedUseIsFile
        )
        var folderPlace: WallpaperPathPlace?
        var folderDecision: FolderAccessDecision?
        var askPath: String?
        var askPlace: WallpaperPathPlace?
        var askVolumeKind = FolderVolumeKind.none
        if let protected {
            let volumeKind = FolderVolumeKindProbe.kind(path: protected.path)
            let accessDecision = FolderAccessPolicy.decide(
                place: protected.place,
                askedLocations: askedLocations,
                lastRead: grantedLocations.contains(protected.place) ? .granted : .unknown,
                volumeKind: volumeKind
            )
            folderPlace = protected.place
            folderDecision = accessDecision
            switch accessDecision {
            case .tryRead:
                let local = protected.place == .icloud ? FolderFileLocality.isLocal(protected.path) : true
                // A readability flag can stay false just after the folder is allowed.
                // The blur render opens the file, so that flag does not keep the plain fill.
                let pictureChoice = FolderPictureChoice.choose(
                    decision: accessDecision,
                    placeAllowsOpen: FolderProbePlan.shouldOpen(place: protected.place, alreadyLocal: local)
                )
                if pictureChoice == .openFile {
                    let source = decision.source == .none ? WallpaperSource.legacy : decision.source
                    decision = (source: source, use: .imageFile(protected.path), kind: .still)
                } else {
                    folderDecision = .fallback
                }
            case .offerAsk:
                askPath = protected.path
                askPlace = protected.place
                askVolumeKind = volumeKind
            case .fallback, .doNotTouch:
                break
            }
        }
        let legacyProtected = workspacePath.map { WallpaperPathPlace.classify($0).isProtected } ?? false
        let skippingProtected = access.protected || (legacyProtected && decision.use == .plainBlur && (choice == nil || choice?.provider == WallpaperStoreIndex.imageProvider))
        let urlLog: String
        if !access.protected && (access.reason == "unreadable" || decision.kind == .unreadable) {
            urlLog = WallpaperURLLog.line(
                shape: choice?.urlShape ?? "none",
                filesCount: choice?.filesCount ?? 0,
                pathParsed: access.pathParsed,
                exists: access.exists,
                readable: access.readable,
                place: access.place,
                ext: access.ext,
                reason: "unreadable"
            )
        } else if access.protected && folderDecision != .tryRead {
            urlLog = WallpaperURLLog.protected(
                shape: choice?.urlShape ?? "none",
                filesCount: choice?.filesCount ?? 0,
                pathParsed: access.pathParsed,
                place: access.place,
                ext: access.ext
            )
        } else if folderDecision == .tryRead, let folderPlace {
            urlLog = WallpaperURLLog.line(
                shape: choice?.urlShape ?? "String",
                filesCount: choice?.filesCount ?? 0,
                pathParsed: true,
                exists: "true",
                readable: "true",
                place: folderPlace.rawValue,
                ext: WallpaperPathPlace.ext(of: protected?.path ?? ""),
                reason: "allowed"
            )
        } else if skippingProtected, let workspacePath {
            urlLog = WallpaperURLLog.protected(
                shape: "String",
                filesCount: 0,
                pathParsed: true,
                place: WallpaperPathPlace.classify(workspacePath).rawValue,
                ext: WallpaperPathPlace.ext(of: workspacePath)
            )
        } else if choice?.provider == WallpaperStoreIndex.imageProvider {
            var reason = access.reason
            if decision.kind == .unreadable {
                reason = "unreadable"
            } else if decision.source == .legacy {
                reason = "legacy"
            }
            urlLog = WallpaperURLLog.line(
                shape: choice?.urlShape ?? "none",
                filesCount: choice?.filesCount ?? 0,
                pathParsed: access.pathParsed,
                exists: access.exists,
                readable: access.readable,
                place: access.place,
                ext: access.ext,
                reason: reason
            )
        } else {
            urlLog = ""
        }
        let aerial = WallpaperAerialFiles.resolution(for: choice)
        let matchLog: String
        if choice?.provider == WallpaperStoreIndex.colorProvider {
            let name = choice?.systemColorName ?? "none"
            let matched = choice?.systemColorName != nil && choice?.solidColor != nil
            matchLog = "matched=\(matched) name=\(name)"
        } else if choice?.provider == WallpaperStoreIndex.aerialsProvider {
            matchLog = aerial.matchLog
        } else {
            matchLog = ""
        }
        let scale = max(screen.backingScaleFactor, 1)
        let pixelW = max(1, Int((screen.frame.width * scale).rounded()))
        let pixelH = max(1, Int((screen.frame.height * scale).rounded()))
        var kind = WallpaperKind.fallback
        var url: URL?
        var imageIndex = 0
        var color: WallpaperSolidColor?
        var token = "plain"
        switch decision.use {
        case .imageFile(let path):
            let picturePlace = WallpaperPathPlace.classify(path)
            if picturePlace.isProtected {
                let local = picturePlace == .icloud ? FolderFileLocality.isLocal(path) : true
                let allowed = grantedLocations.contains(picturePlace)
                    && FolderProbePlan.shouldOpen(place: picturePlace, alreadyLocal: local)
                if !allowed {
                    kind = .fallback
                    color = WallpaperNeutralFill.color(for: .dark)
                    token = "protected"
                    break
                }
            }
            let read = WallpaperFileMetadata.read(at: URL(fileURLWithPath: path))
            kind = WallpaperClassifier.kind(hints: read.hints, imageCount: read.imageCount)
            let granted = picturePlace.isProtected && grantedLocations.contains(picturePlace)
            let frame = GrantedPictureFrame.resolve(
                classified: WallpaperClassifier.frame(
                    kind: kind,
                    hints: read.hints,
                    appearance: appearance,
                    imageCount: read.imageCount
                ),
                imageCount: read.imageCount,
                accessGranted: granted
            )
            switch frame {
            case .index(let index):
                url = URL(fileURLWithPath: path)
                imageIndex = index
                kind = granted && read.imageCount == 0 ? .still : kind
                token = path
                color = nil
            case .plainBlur:
                color = WallpaperNeutralFill.color(for: appearance)
                token = "neutral"
            }
        case .solid(let fill):
            kind = .solidColor
            color = fill
            token = colorToken(fill)
        case .plainBlur:
            kind = decision.kind
            if decision.kind == .unreadable {
                color = WallpaperNeutralFill.color(for: .dark)
                token = "unreadable"
            } else if skippingProtected {
                color = WallpaperNeutralFill.color(for: .dark)
                token = "protected"
            } else {
                color = WallpaperNeutralFill.color(for: appearance)
                token = "neutral"
            }
        }
        var shownAerial: String?
        if choice?.provider == WallpaperStoreIndex.aerialsProvider {
            if let movie = aerial.movie, movie.isFileURL, let assetID = aerial.assetID {
                kind = .still
                url = movie
                imageIndex = 0
                color = nil
                token = assetID
                shownAerial = assetID
            } else {
                kind = .fallback
                url = nil
                imageIndex = 0
                color = WallpaperNeutralFill.color(for: appearance)
                token = "neutral"
            }
        }
        return DesktopPictureJob(
            cacheKey: WallpaperCacheIdentity.key(
                token: token,
                pixelWidth: pixelW,
                pixelHeight: pixelH,
                // The Aerial still does not depend on Light or Dark, so the cache
                // stays warm when the system appearance changes.
                appearance: shownAerial == nil ? appearance : .light,
                kind: kind,
                imageIndex: url == nil ? nil : imageIndex,
                storeModified: stored.modified
            ),
            url: url,
            imageIndex: imageIndex,
            kind: kind,
            appearance: appearance,
            reportedSystemDefault: workspacePath.map(WallpaperReportedImage.isSystemDefault) ?? false,
            source: decision.source,
            provider: choice?.provider ?? "",
            configKeys: choice?.configKeys ?? [],
            colorValueLog: choice?.colorValueLog ?? "",
            urlLog: urlLog,
            matchLog: matchLog,
            structureLog: choice?.structureLog ?? "",
            solidColor: color,
            aerialAssetID: shownAerial,
            aerialRecord: aerial.record,
            pointSize: screen.frame.size,
            pixelWidth: pixelW,
            pixelHeight: pixelH,
            screenX: Double(screen.frame.origin.x),
            screenY: Double(screen.frame.origin.y),
            screenWidth: Double(screen.frame.size.width),
            screenHeight: Double(screen.frame.size.height),
            askPath: askPath,
            askPlace: askPlace,
            askVolumeKind: askVolumeKind,
            folderPlace: folderPlace,
            folderDecision: folderDecision
        )
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

    static func flatImage(color: WallpaperSolidColor, pixelWidth: Int, pixelHeight: Int, pointSize: NSSize) -> NSImage? {
        guard let cgImage = render(DesktopPictureJob(
            cacheKey: "",
            url: nil,
            imageIndex: 0,
            kind: .solidColor,
            appearance: .dark,
            reportedSystemDefault: false,
            source: .none,
            provider: "",
            configKeys: [],
            colorValueLog: "",
            solidColor: color,
            pointSize: pointSize,
            pixelWidth: max(pixelWidth, 1),
            pixelHeight: max(pixelHeight, 1),
            screenX: 0,
            screenY: 0,
            screenWidth: Double(pointSize.width),
            screenHeight: Double(pointSize.height),
            askPath: nil,
            askPlace: nil,
            askVolumeKind: .none,
            folderPlace: nil,
            folderDecision: nil
        )) else { return nil }
        return NSImage(cgImage: cgImage, size: pointSize)
    }

    static func cached(_ key: String) -> NSImage? {
        key == cacheKey ? cache : nil
    }

    static func store(_ image: NSImage, key: String) {
        cacheKey = key
        cache = image
    }

    /// Drops the plain picture that was kept while a folder was refused.
    /// The next blur is built from the file, not from that fill.
    static func dropRefusedFallback() {
        guard let key = cacheKey,
              WallpaperPictureStore.shouldDropRefusedFallback(cacheKey: key, accessAllowed: true) else {
            return
        }
        cacheKey = nil
        cache = nil
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
    /// `frame` is an Aerial still that was already grabbed. Passing it skips ImageIO.
    static func render(_ job: DesktopPictureJob, frame supplied: CGImage? = nil) -> CGImage? {
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
        if supplied == nil, let color = job.solidColor {
            context.setFillColor(CGColor(
                srgbRed: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: 1
            ))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Same veil the ink decision used for this fill.
            let veil = InkContrast.forFill(color).veil
            return dimmed(context, width: width, height: height, veil: veil)
        } else if let wallpaper = supplied ?? job.url.flatMap({ decodedThumbnail(at: $0, index: job.imageIndex, maxPixelSize: plan.maxPixelSize) }) {
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
        return dimmed(context, width: width, height: height, veil: WallpaperDim.black)
    }

    /// Black veil. A flat fill uses the veil chosen with its ink. A photo keeps the normal veil.
    private static func dimmed(_ context: CGContext, width: Int, height: Int, veil: Double) -> CGImage? {
        context.setFillColor(CGColor(gray: 0, alpha: CGFloat(veil)))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// Checks a picture path only after its folder is known from the text.
/// Desktop, Documents, Downloads, Photos, iCloud Drive, and external volumes stay closed
/// until that place has been allowed. Bookmark data is not resolved, because resolving it reads the file.
enum WallpaperFileAccess {
    struct Report {
        var usablePath: String?
        var pathParsed: Bool
        var exists: String
        var readable: String
        var place: String
        var ext: String
        var reason: String
        var storeFileExists: Bool
        var locationBlocked: Bool
        var protected: Bool
    }

    struct Look {
        var exists: Bool
        var readable: Bool
    }

    static let empty = Report(
        usablePath: nil,
        pathParsed: false,
        exists: "false",
        readable: "false",
        place: "other",
        ext: "none",
        reason: "none",
        storeFileExists: false,
        locationBlocked: false,
        protected: false
    )

    static func inspect(_ choice: WallpaperStoreChoice?) -> Report {
        guard let choice, choice.provider == WallpaperStoreIndex.imageProvider, !choice.isFolder else {
            return empty
        }
        let listed = choice.imageCandidates.isEmpty
            ? (choice.imageFilePath.map { [$0] } ?? [])
            : choice.imageCandidates
        let plan = WallpaperFileGate.plan(paths: listed)
        if plan.statPaths.isEmpty {
            if let place = plan.blockedPlace {
                return blocked(place: place, ext: plan.blockedExt, parsed: plan.pathParsed)
            }
            return Report(
                usablePath: nil,
                pathParsed: plan.pathParsed,
                exists: "false",
                readable: "false",
                place: "other",
                ext: "none",
                reason: "missing",
                storeFileExists: false,
                locationBlocked: false,
                protected: false
            )
        }
        if let found = status(of: plan.statPaths) {
            return found
        }
        if let place = plan.blockedPlace {
            return blocked(place: place, ext: plan.blockedExt, parsed: true)
        }
        let path = plan.statPaths[0]
        return Report(
            usablePath: nil,
            pathParsed: true,
            exists: "false",
            readable: "false",
            place: WallpaperPathPlace.classify(path).rawValue,
            ext: WallpaperPathPlace.ext(of: path),
            reason: "missing",
            storeFileExists: false,
            locationBlocked: false,
            protected: false
        )
    }

    /// Nil means the path was left closed or is not absolute, so the file was not touched.
    /// A protected path is opened only after that place has been allowed.
    static func look(_ path: String, includingProtected: Bool = false) -> Look? {
        let normalized = WallpaperPathPlace.normalized(path)
        let place = WallpaperPathPlace.classify(normalized)
        if (place.isProtected && !includingProtected) || !normalized.hasPrefix("/") {
            return nil
        }
        var directory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &directory)
        if !exists || directory.boolValue {
            return Look(exists: false, readable: false)
        }
        return Look(exists: true, readable: FileManager.default.isReadableFile(atPath: normalized))
    }

    private static func blocked(place: WallpaperPathPlace, ext: String, parsed: Bool) -> Report {
        Report(
            usablePath: nil,
            pathParsed: parsed,
            exists: "skipped",
            readable: "skipped",
            place: place.rawValue,
            ext: ext,
            reason: "protected",
            storeFileExists: false,
            locationBlocked: true,
            protected: true
        )
    }

    /// The paths have already been classified as safe. Protected paths are ignored again here.
    private static func status(of paths: [String]) -> Report? {
        var unreadable: Report?
        for path in paths {
            if WallpaperPathPlace.classify(path).isProtected || !path.hasPrefix("/") { continue }
            var directory = ObjCBool(false)
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
            if !exists || directory.boolValue { continue }
            let place = WallpaperPathPlace.classify(path).rawValue
            let ext = WallpaperPathPlace.ext(of: path)
            if FileManager.default.isReadableFile(atPath: path) {
                return Report(
                    usablePath: path,
                    pathParsed: true,
                    exists: "true",
                    readable: "true",
                    place: place,
                    ext: ext,
                    reason: "storeFile",
                    storeFileExists: true,
                    locationBlocked: false,
                    protected: false
                )
            }
            if unreadable == nil {
                unreadable = Report(
                    usablePath: nil,
                    pathParsed: true,
                    exists: "true",
                    readable: "false",
                    place: place,
                    ext: ext,
                    reason: "unreadable",
                    storeFileExists: true,
                    locationBlocked: false,
                    protected: false
                )
            }
        }
        return unreadable
    }
}

enum WallpaperArchivedColor {
    static func color(from data: Data) -> WallpaperSolidColor? {
        guard WallpaperKeyedArchive.isKeyedArchive(data),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data),
              let rgb = color.usingColorSpace(.sRGB) else {
            return nil
        }
        return WallpaperSolidColor(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
    }
}

/// The wallpaper the system recorded for this display. Missing or unreadable means
/// the workspace image URL is the only picture available.
/// A sandboxed App Store build cannot read this file. Photos still come from
/// the legacy picture URL; every other wallpaper then uses the plain blur.
enum WallpaperSolidColors {
    static func normalizedNames() -> [String] {
        let directory = WallpaperStoreIndex.solidColorsDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return names
            .filter { $0.lowercased().hasSuffix(".png") }
            .map { WallpaperSolidColorMatch.normalize((($0 as NSString).deletingPathExtension)) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    static func existingFile(matching name: String) -> String? {
        let directory = WallpaperStoreIndex.solidColorsDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory),
              let file = WallpaperSolidColorMatch.fileName(matching: name, candidates: names) else {
            return nil
        }
        return (directory as NSString).appendingPathComponent(file)
    }
}

/// The Aerial catalogue and the downloaded movies. Nothing here is logged.
enum WallpaperAerialFiles {
    struct Resolution {
        var assetID: String?
        var record: String
        var movie: URL?
        var matchLog: String
    }

    static func resolution(for choice: WallpaperStoreChoice?) -> Resolution {
        guard choice?.provider == WallpaperStoreIndex.aerialsProvider else {
            return Resolution(assetID: nil, record: "", movie: nil, matchLog: "")
        }
        let catalogue: Any? = choice?.aerialAssetID == nil && choice?.aerialSubcategory != nil ? loadCatalogue() : nil
        let assetID = WallpaperAerialCatalogue.resolvedAssetID(
            storedAssetID: choice?.aerialAssetID,
            subcategory: choice?.aerialSubcategory,
            catalogue: catalogue
        )
        let movie = WallpaperAerialCatalogue.localMovie(assetID: assetID, videosDirectory: videosDirectory())
        return Resolution(
            assetID: assetID,
            record: choice?.aerialRecord ?? "",
            movie: movie,
            matchLog: WallpaperAerialLog.matchLine(matched: movie != nil, assetID: assetID)
        )
    }

    private static var cachedCatalogue: (stamp: TimeInterval, value: Any?)?

    private static func videosDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos", isDirectory: true)
    }

    private static func loadCatalogue() -> Any? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json")
        let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        if let cached = cachedCatalogue, cached.stamp == stamp, stamp != 0 {
            return cached.value
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if stamp != 0 {
            cachedCatalogue = (stamp, object)
        }
        return object
    }
}

enum WallpaperStoreReader {
    struct Snapshot {
        var choice: WallpaperStoreChoice?
        var modified: TimeInterval
    }

    static func load() -> Snapshot {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        guard let data = try? Data(contentsOf: url),
              let store = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return Snapshot(choice: nil, modified: modified)
        }
        return Snapshot(choice: WallpaperStoreIndex.choice(in: store, displayUUID: mainDisplayUUID()), modified: modified)
    }

    private static func mainDisplayUUID() -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else {
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
