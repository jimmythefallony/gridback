import AppKit
import GridBackCore
import os
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var model: GridBackModel?
    private var monitor: Any?
    private var settingsWindow: NSWindow?
    /// Settings became key, or was shown again. The folder line refreshes from here, not from the view.
    var onNeedsRefresh: (() -> Void)?

    func show(model: GridBackModel, loginItem: LoginItemModel) {
        self.model = model
        loginItem.refresh()
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model, loginItem: loginItem))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "GridBack Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 460, height: 640))
            // A floating window would cover System Settings after the privacy link.
            window.level = .normal
            settingsWindow = window
        }
        NSApp.unhide(nil)
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        onNeedsRefresh?()
    }

    var isVisible: Bool {
        settingsWindow?.isVisible == true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onNeedsRefresh?()
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func stopRecording() {
        monitor.map { NSEvent.removeMonitor($0) }
        monitor = nil
        model?.cancelShortcutRecording()
    }

    /// Called from the app-wide key monitor while the settings window is key.
    func consumeRecordingKey(_ event: NSEvent) -> Bool {
        guard model?.isRecordingShortcut == true, settingsWindow?.isKeyWindow == true else {
            return false
        }
        if event.isARepeat {
            return true
        }
        if event.keyCode == SearchKeyRouting.escapeKeyCode {
            stopRecording()
            return true
        }
        switch ShortcutCapture.interpret(event) {
        case .success(let chord):
            model?.tryAdoptShortcut(chord)
        case .failure(let rejection):
            model?.noteShortcutRejection(rejection)
        }
        return true
    }
}

/// Opens Files & Folders. If that pane cannot be opened, Security is opened instead.
enum PrivacySettingsLink {
    static let filesAndFolders = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    static let security = "x-apple.systempreferences:com.apple.preference.security"

    static func open() {
        if let files = URL(string: filesAndFolders), NSWorkspace.shared.open(files) {
            return
        }
        if let security = URL(string: security) {
            NSWorkspace.shared.open(security)
        }
    }
}

/// Keeps the Settings line in step with the current wallpaper.
/// A quiet read runs only for Allowed and Not allowed, off the main thread, and never for a folder
/// that has not been decided. That read can raise the system prompt.
final class FolderSettingsController {
    private weak var model: GridBackModel?
    private weak var overlay: OverlayController?
    private weak var explainer: FolderExplainerController?
    private var settingsOpen: () -> Bool = { false }
    private var picture: FolderAccessPicture?
    private var volumeKind = FolderVolumeKind.none
    private var denial = FolderDenialCache()
    private var probeWork: DispatchWorkItem?
    private var probeInFlight = false
    private var probeAgain = false
    private var refreshTicket = 0
    private var watcher: DirectoryWatcher?
    private var desktopObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "folder-access")
    private let diagnosticLog = Logger(subsystem: "com.jimmythefallony.GridBack", category: "settings")

    private static let probeDelay: TimeInterval = 0.5

    deinit {
        probeWork?.cancel()
        watcher?.stop()
        if let desktopObserver {
            DistributedNotificationCenter.default().removeObserver(desktopObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func attach(
        model: GridBackModel,
        overlay: OverlayController,
        explainer: FolderExplainerController,
        settingsOpen: @escaping () -> Bool
    ) {
        self.model = model
        self.overlay = overlay
        self.explainer = explainer
        self.settingsOpen = settingsOpen
    }

    /// Classifies the current wallpaper once. A quiet read waits for a later trigger.
    func start() {
        guard desktopObserver == nil else { return }
        desktopObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.desktop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.wallpaperChanged()
        }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.settingsOpen() else { return }
            self.refreshLine()
            self.scheduleProbe()
        }
        let store = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        let watcher = DirectoryWatcher()
        watcher.start(paths: [store.path]) { [weak self] in
            self?.wallpaperChanged()
        }
        self.watcher = watcher
        refreshLine()
    }

    func settingsBecameKey() {
        refreshLine()
        scheduleProbe()
    }

    func offerCurrent() {
        guard let picture else { return }
        explainer?.offer(place: picture.place, path: picture.path, volumeKind: volumeKind)
    }

    private func wallpaperChanged() {
        refreshLine()
        scheduleProbe()
    }

    private func refreshLine() {
        refreshTicket += 1
        let ticket = refreshTicket
        let workspacePath = currentWorkspacePath()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let resolved = Self.resolve(workspacePath)
            DispatchQueue.main.async {
                guard let self, self.refreshTicket == ticket else { return }
                self.apply(resolved)
            }
        }
    }

    /// Coalesces a burst of triggers, then allows one read at a time.
    private func scheduleProbe() {
        probeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.beginProbe()
        }
        probeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeDelay, execute: work)
    }

    private func beginProbe() {
        guard !probeInFlight else {
            probeAgain = true
            return
        }
        probeInFlight = true
        let workspacePath = currentWorkspacePath()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let resolved = Self.resolve(workspacePath)
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(resolved)
                // An in-flight system prompt already has the main thread. Wait, and do not start a second read.
                guard !FolderAccessRead.isWaitingForSystemPrompt else {
                    self.probeAgain = true
                    self.endProbe()
                    return
                }
                guard let picture = self.picture,
                      let status = self.model?.folderAccessStatus,
                      FolderAccessStatus.mayProbeSilently(status) else {
                    self.endProbe()
                    return
                }
                let path = picture.path
                let place = picture.place
                FolderAccessRead.start(path: path, place: place) { [weak self] granted in
                    self?.completeProbe(granted: granted, path: path, place: place)
                }
            }
        }
    }

    private func completeProbe(granted: Bool, path: String, place: WallpaperPathPlace) {
        defer { endProbe() }
        let pathHash = DiagnosticPathHash.number(for: path)
        DiagnosticProbeNote.record(pathHash)
        guard picture?.path == path, picture?.place == place, let model else {
            logSettingsProbe(granted: granted, pathHash: pathHash, prewarm: 0)
            return
        }
        denial = model.applyFolderRecheck(
            succeeded: granted,
            place: place,
            path: path,
            denial: denial
        )
        let decision: FolderAccessDecision = granted ? .tryRead : .fallback
        log.info("\(FolderAccessLog.line(place: place, decision: decision), privacy: .public)")
        let prewarm = granted && model.isOverlayVisible != true ? 1 : 0
        logSettingsProbe(granted: granted, pathHash: pathHash, prewarm: prewarm)
        if prewarm == 1 {
            overlay?.preparePictureForNextOpen()
        }
    }

    private func logSettingsProbe(granted: Bool, pathHash: UInt32, prewarm: Int) {
        let resultName = DiagnosticProbeResult(granted: granted).logName
        let hash = Int(pathHash)
        let ms = DiagnosticClock.milliseconds
        diagnosticLog.info("settings probe ms=\(ms, privacy: .public) result=\(resultName, privacy: .public) pathHash=\(hash, privacy: .public) prewarm=\(prewarm, privacy: .public)")
    }

    private func endProbe() {
        probeInFlight = false
        if probeAgain {
            probeAgain = false
            scheduleProbe()
        }
    }

    private func apply(_ resolved: (picture: FolderAccessPicture?, volumeKind: FolderVolumeKind)) {
        picture = resolved.picture
        volumeKind = resolved.volumeKind
        model?.noteFolderSubject(place: resolved.picture?.place, volumeKind: resolved.volumeKind)
    }

    private func currentWorkspacePath() -> String? {
        guard let screen = PrimaryDisplay.screen() else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)?.path
    }

    /// The store file and the volume list. The wallpaper image itself is not opened.
    private static func resolve(_ workspacePath: String?) -> (picture: FolderAccessPicture?, volumeKind: FolderVolumeKind) {
        let choice = WallpaperStoreReader.load().choice
        let storePaths = choice.map { candidate in
            candidate.imageCandidates.isEmpty
                ? (candidate.imageFilePath.map { [$0] } ?? [])
                : candidate.imageCandidates
        } ?? []
        let picture = FolderAccessTarget.picture(
            provider: choice?.provider,
            isFolder: choice?.isFolder ?? false,
            storePaths: storePaths,
            workspacePath: workspacePath
        )
        let kind = picture.map { FolderVolumeKindProbe.kind(path: $0.path) } ?? .none
        return (picture, kind)
    }
}
