import AppKit
import GridBackCore
import os
import SwiftUI

/// A small titled window that explains the folder ask. It is not the grid.
/// Closing it is Not now: the place is remembered and is not offered again.
final class FolderExplainerController: NSObject, NSWindowDelegate {
    private var model: GridBackModel?
    private var overlay: OverlayController?
    private var window: NSWindow?
    private var shownPlace: WallpaperPathPlace?
    private var rememberedPath: String?
    /// True while the window is being hidden without an answer, including when the grid opens.
    private var suspending = false
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "folder-access")

    func attach(model: GridBackModel, overlay: OverlayController) {
        self.model = model
        self.overlay = overlay
    }

    /// Launch, a grid close, or the end of a drag. Does nothing while the grid is open.
    func considerCurrentWallpaper() {
        guard let model, !model.isOverlayVisible else { return }
        guard let screen = PrimaryDisplay.screen() else { return }
        let job = DesktopPicture.job(
            on: screen,
            askedLocations: model.folderAsked,
            grantedLocations: model.folderGranted
        )
        guard let place = job.askPlace, let path = job.askPath else {
            _ = model.clearFolderExplainer()
            suspend()
            rememberedPath = nil
            return
        }
        let step = model.noteFolderWallpaper(
            place: place,
            volumeKind: job.askVolumeKind,
            gridClosed: true,
            dragActive: model.folderDragActive
        )
        apply(step, path: path)
    }

    /// The grid is opening. Hide the explainer and keep the offer unanswered.
    func gridOpened() {
        _ = model?.folderExplainerGridOpened()
        suspend()
    }

    /// The grid just closed. Returns true when the explainer is on screen.
    func gridClosed() -> Bool {
        considerCurrentWallpaper()
        return window?.isVisible == true
    }

    func dragEnded() {
        considerCurrentWallpaper()
    }

    private func apply(_ step: FolderExplainerStep, path: String) {
        switch step {
        case .idle:
            rememberedPath = nil
            suspend()
        case .wait:
            rememberedPath = path
            suspend()
        case .show(let place):
            rememberedPath = path
            show(place)
        }
    }

    private func show(_ place: WallpaperPathPlace) {
        if shownPlace == place, window?.isVisible == true { return }
        shownPlace = place
        let hosting = NSHostingController(rootView: FolderExplainerView(
            message: FolderExplainerCopy.message(place: place),
            allow: { [weak self] in self?.allow() },
            notNow: { [weak self] in self?.notNow() }
        ))
        // Automatic sizing uses a bad height the first time and a one-word width the next.
        hosting.sizingOptions = .init()
        let size = contentSize(of: hosting)
        hosting.preferredContentSize = size
        let window = self.window ?? makeWindow()
        window.contentViewController = hosting
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        self.window = window
        window.center()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Lay the text out at the fixed width, then keep that width even if the measurement collapses.
    private func contentSize(of hosting: NSHostingController<FolderExplainerView>) -> NSSize {
        let width = CGFloat(FolderExplainerLayout.width)
        hosting.view.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(FolderExplainerLayout.maximumHeight))
        hosting.view.layoutSubtreeIfNeeded()
        let measured = hosting.sizeThatFits(in: NSSize(width: width, height: CGFloat(FolderExplainerLayout.maximumHeight)))
        let chosen = FolderExplainerLayout.size(
            measuredWidth: Double(measured.width),
            measuredHeight: Double(measured.height)
        )
        return NSSize(width: chosen.width, height: chosen.height)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: CGFloat(FolderExplainerLayout.width), height: CGFloat(FolderExplainerLayout.minimumHeight)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "GridBack")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.level = .normal
        // Follow the Space the user is on, including away from a full-screen app.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        return window
    }

    private func allow() {
        guard let model, let place = shownPlace, let path = rememberedPath else { return }
        suspending = true
        window?.orderOut(nil)
        suspending = false
        shownPlace = nil
        rememberedPath = nil
        guard let record = model.allowFolderAccess(), record.place == place, record.readAfter else { return }
        let overlay = self.overlay
        let log = self.log
        FolderAccessRead.start(path: path, place: place) { [weak model] granted in
            if granted {
                model?.noteFolderGranted(place)
                if model?.isOverlayVisible != true {
                    overlay?.preparePictureForNextOpen()
                }
            } else {
                model?.noteFolderDenied(place)
            }
            let decision: FolderAccessDecision = granted ? .tryRead : .fallback
            log.info("\(FolderAccessLog.line(place: place, decision: decision), privacy: .public)")
        }
    }

    private func notNow() {
        guard !suspending else { return }
        window?.close()
    }

    private func suspend() {
        suspending = true
        window?.orderOut(nil)
        suspending = false
        shownPlace = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard !suspending else { return }
        suspending = true
        shownPlace = nil
        rememberedPath = nil
        if let record = model?.declineFolderAccess() {
            log.info("\(FolderAccessLog.line(place: record.place, decision: .fallback), privacy: .public)")
        }
        suspending = false
    }
}

/// The explainer text and the two answers. The message names the folder kind, not a path.
private struct FolderExplainerView: View {
    var message: String
    var allow: () -> Void
    var notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Not now"), action: notNow)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Allow"), action: allow)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: CGFloat(FolderExplainerLayout.width))
        .fixedSize(horizontal: true, vertical: true)
    }
}

/// Network or removable, from the volumes the system already lists. The wallpaper file is not opened.
enum FolderVolumeKindProbe {
    static func kind(path: String) -> FolderVolumeKind {
        guard WallpaperPathPlace.classify(path) == .volumes else { return .none }
        let normalized = WallpaperPathPlace.normalized(path)
        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsRemovableKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) ?? []
        var matched: URL?
        var matchedRoot = ""
        for url in urls {
            let root = WallpaperPathPlace.normalized(url.path)
            guard root != "/", normalized == root || normalized.hasPrefix(root + "/") else { continue }
            if root.count > matchedRoot.count {
                matched = url
                matchedRoot = root
            }
        }
        guard let matched else { return .none }
        let values = try? matched.resourceValues(forKeys: keys)
        if values?.volumeIsLocal == false { return .network }
        if values?.volumeIsRemovable == true { return .removable }
        return .none
    }
}

/// Whether an iCloud file is already on this Mac. Checking this does not download it.
enum FolderFileLocality {
    static func isLocal(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: WallpaperPathPlace.normalized(path))
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        if values.isUbiquitousItem != true { return true }
        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return true
        default:
            return false
        }
    }
}

/// One deliberate read of the first bytes of the wallpaper file.
/// The read runs off the main thread so the system prompt can appear, and it never runs while the grid is opening.
enum FolderAccessRead {
    private static let queue = DispatchQueue(
        label: "com.jimmythefallony.GridBack.folder-access",
        qos: .userInitiated
    )

    private static let waitingLock = NSLock()
    private static var waitingForSystemPrompt = false

    /// True from the moment the deliberate read is scheduled until the person has answered.
    static var isWaitingForSystemPrompt: Bool {
        waitingLock.lock()
        defer { waitingLock.unlock() }
        return waitingForSystemPrompt
    }

    private static func setWaiting(_ waiting: Bool) {
        waitingLock.lock()
        waitingForSystemPrompt = waiting
        waitingLock.unlock()
    }

    static func start(path: String, place: WallpaperPathPlace, done: @escaping (Bool) -> Void) {
        setWaiting(true)
        queue.async {
            let granted = readFirstBytes(path: path, place: place)
            DispatchQueue.main.async {
                setWaiting(false)
                done(granted)
            }
        }
    }

    /// A call on the main thread returns without opening the file.
    /// The system prompt needs the main thread, so this read must not occupy it.
    private static func readFirstBytes(path: String, place: WallpaperPathPlace) -> Bool {
        if Thread.isMainThread { return false }
        let normalized = WallpaperPathPlace.normalized(path)
        guard WallpaperPathPlace.classify(normalized) == place else { return false }
        let local = place == .icloud ? FolderFileLocality.isLocal(normalized) : true
        guard FolderProbePlan.shouldOpen(place: place, alreadyLocal: local) else { return false }
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: normalized))
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 16)
            return true
        } catch {
            return false
        }
    }
}
