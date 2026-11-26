import AppKit
import GridBackCore
import os
import SwiftUI

/// A non-modal panel styled like a system alert. It is not the grid.
/// Closing it is Not Now: the place is remembered and is not offered again.
final class FolderExplainerController: NSObject, NSWindowDelegate {
    private var model: GridBackModel?
    private var overlay: OverlayController?
    private var window: NSPanel?
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

    /// Allow or Ask again from Settings. The existing window is used, and only when the grid is closed.
    func offer(place: WallpaperPathPlace, path: String, volumeKind: FolderVolumeKind) {
        guard let model else { return }
        let step = model.noteFolderWallpaper(
            place: place,
            volumeKind: volumeKind,
            gridClosed: !model.isOverlayVisible,
            dragActive: model.folderDragActive
        )
        apply(step, path: path)
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
            title: FolderExplainerCopy.title,
            message: FolderExplainerCopy.body(place: place) ?? "",
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
        // Once, when the panel is shown. Space changes do not activate again.
        NSApp.activate()
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

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: CGFloat(FolderExplainerLayout.width), height: CGFloat(FolderExplainerLayout.minimumHeight)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        // Present on every Space, including the desktop and a full-screen app.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func allow() {
        guard let model, let place = shownPlace, let path = rememberedPath else { return }
        suspending = true
        window?.orderOut(nil)
        suspending = false
        shownPlace = nil
        rememberedPath = nil
        guard let record = model.allowFolderAccess(), record.place == place, record.readAfter else { return }
        model.noteFolderReadStarted()
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

/// Alert-shaped content. VoiceOver reads the title, then the body, then the buttons.
private struct FolderExplainerView: View {
    var title: String
    var message: String
    var allow: () -> Void
    var notNow: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            AlertButtonRow(notNow: notNow, allow: allow)
                .padding(.top, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(width: CGFloat(FolderExplainerLayout.width))
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

/// Two equal buttons across the text width, the same shape as a system alert.
private struct AlertButtonRow: NSViewRepresentable {
    var notNow: () -> Void
    var allow: () -> Void

    func makeNSView(context: Context) -> AlertButtonBox {
        let box = AlertButtonBox()
        box.notNow = notNow
        box.allow = allow
        return box
    }

    func updateNSView(_ box: AlertButtonBox, context: Context) {
        box.notNow = notNow
        box.allow = allow
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AlertButtonBox, context: Context) -> CGSize? {
        let width = proposal.width ?? CGFloat(FolderExplainerLayout.width)
        let height = nsView.fittingSize.height
        return CGSize(width: width, height: height)
    }
}

private final class AlertButtonBox: NSView {
    var notNow: () -> Void = {}
    var allow: () -> Void = {}

    private let decline = NSButton()
    private let proceed = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        decline.title = String(localized: "Not Now")
        decline.bezelStyle = .rounded
        decline.controlSize = .large
        decline.keyEquivalent = "\u{1b}"
        decline.target = self
        decline.action = #selector(didDecline)

        proceed.title = String(localized: "Continue")
        proceed.bezelStyle = .rounded
        proceed.controlSize = .large
        proceed.keyEquivalent = "\r"
        proceed.target = self
        proceed.action = #selector(didAllow)

        decline.translatesAutoresizingMaskIntoConstraints = false
        proceed.translatesAutoresizingMaskIntoConstraints = false
        addSubview(decline)
        addSubview(proceed)
        NSLayoutConstraint.activate([
            decline.leadingAnchor.constraint(equalTo: leadingAnchor),
            decline.topAnchor.constraint(equalTo: topAnchor),
            decline.bottomAnchor.constraint(equalTo: bottomAnchor),
            proceed.leadingAnchor.constraint(equalTo: decline.trailingAnchor, constant: 8),
            proceed.trailingAnchor.constraint(equalTo: trailingAnchor),
            proceed.topAnchor.constraint(equalTo: topAnchor),
            proceed.bottomAnchor.constraint(equalTo: bottomAnchor),
            decline.widthAnchor.constraint(equalTo: proceed.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: decline.intrinsicContentSize.height)
    }

    @objc private func didDecline() {
        notNow()
    }

    @objc private func didAllow() {
        allow()
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
        if values?.volumeIsLocal == true { return .fixed }
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
/// The read runs off the main thread. A silent re-check may run while the grid is open,
/// and only for a folder that was already allowed or refused, so the system prompt stays closed.
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
