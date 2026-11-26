import AppKit
import Foundation
import GridBackCore
import os

protocol GridBackUIDelegate: AnyObject {
    func gridBackShowOverlay()
    func gridBackHideOverlay()
    func gridBackShowSettings()
    func gridBackDragEnded()
    func gridBackOfferFolderExplainer()
    func gridBackOpenPrivacySettings()
}

/// Main-thread coordinator for the menu bar, overlay, catalog, and saved layout.
final class GridBackModel: ObservableObject {
    static let shared = GridBackModel()

    @Published private(set) var layout: Layout
    @Published private(set) var appsByID: [String: AppRecord] = [:]
    @Published private(set) var searchQuery = ""
    @Published private(set) var currentPage = 0
    @Published private(set) var openFolderID: String?
    @Published private(set) var folderCloseRequest = 0
    private var folderCloseInFlight = false
    @Published private(set) var selectedResultIndex = 0
    @Published private(set) var isOverlayVisible = false
    /// Icon-page zoom. Search, Settings, and the folder explainer keep reading `isOverlayVisible`.
    @Published private(set) var fadePhase: GridFade.Phase = .closed
    @Published private(set) var launchError: String?
    @Published private(set) var shortcut: ShortcutChord
    @Published var heldDrag = HeldDrag() {
        didSet {
            if oldValue.isActive, !heldDrag.isActive, !pointerDragActive {
                delegate?.gridBackDragEnded()
            }
        }
    }
    @Published private(set) var hotkeyFailure: String?
    @Published private(set) var persistenceWarning: String?
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var shortcutStatus: String?
    @Published private(set) var isScanning = true
    @Published private(set) var iconImages: [String: NSImage] = [:]
    /// Shown after the first Command-Q while a GridBack window is key.
    @Published private(set) var quitNote: String?
    /// Bumps on each arm so the note can fade again.
    @Published private(set) var quitNoteID = 0
    /// Menu bar and Dock space taken from the screen's visible frame. Zero on
    /// an edge means that edge is not reserved, including an auto-hidden Dock.
    @Published private(set) var screenReserve = ScreenReserve.none
    /// Foreground ink for the open grid. The overlay sets this with the backdrop.
    @Published private(set) var ink: Ink = .light
    /// The Settings line for the current wallpaper folder. The view only reads this.
    @Published private(set) var folderAccessStatus: FolderAccessStatus = .notNeeded
    @Published private(set) var folderAccessPlace: WallpaperPathPlace?
    @Published private(set) var folderAccessVolumeKind = FolderVolumeKind.none
    /// False until the current wallpaper has been classified. The view stays blank until then.
    @Published private(set) var folderAccessReady = false
    /// True while Apple's folder prompt is waiting, so the Settings button is not pressed again.
    @Published private(set) var folderAccessBusy = false

    weak var delegate: GridBackUIDelegate?

    private let store: PersistenceStore
    /// Places the explainer has offered, and places whose read was allowed. Kept across layout saves.
    private var explainer = FolderExplainerSession()
    /// A pointer drag that lives in the grid view, separate from a held folder drag.
    private var pointerDragActive = false
    private let catalog = AppCatalog()
    private let launcher = AppLauncher()
    private let hotkey = GlobalHotkeyCenter()
    private let watcher = DirectoryWatcher()
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "app")
    private var hasSavedLayout = false
    private var persistEnabled = true
    private var didStart = false
    private var scanInFlight = false
    private var scanQueued = false
    private var launchErrorTicket = 0
    private var quitConfirmation = QuitConfirmation()
    private var quitNoteTicket = 0

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var searchResults: [AppRecord] {
        let ordered = layout.orderedIDs.compactMap { appsByID[$0] }
        return SearchMatcher.filter(ordered, query: searchQuery)
    }

    var shortcutMenuTitle: String {
        String(localized: "Shortcut: \(shortcut.displayString)")
    }

    init(store: PersistenceStore? = nil) {
        let resolved = store ?? PersistenceStore(directoryURL: GridBackModel.supportDirectory())
        self.store = resolved
        switch GridBackModel.loadInitial(from: resolved) {
        case .loaded(let state):
            layout = state.layout
            shortcut = state.shortcut
            explainer = FolderExplainerSession(
                asked: state.askedLocations,
                granted: state.grantedLocations,
                denied: state.deniedLocations
            )
            hasSavedLayout = true
        case .missing:
            layout = Layout(pages: [], metrics: .classic)
            shortcut = .default
        case .failed(let message, let allowSave):
            layout = Layout(pages: [], metrics: .classic)
            shortcut = .default
            persistenceWarning = message
            persistEnabled = allowSave
        }
    }

    func updateScreenReserve(_ reserve: ScreenReserve) {
        guard reserve != screenReserve else { return }
        screenReserve = reserve
    }

    var folderAsked: Set<WallpaperPathPlace> { explainer.asked }
    var folderGranted: Set<WallpaperPathPlace> { explainer.granted }
    var folderDenied: Set<WallpaperPathPlace> { explainer.denied }
    var folderDragActive: Bool { heldDrag.isActive || pointerDragActive }

    func setPointerDragActive(_ active: Bool) {
        guard active != pointerDragActive else { return }
        let wasDragging = folderDragActive
        pointerDragActive = active
        if wasDragging, !folderDragActive {
            delegate?.gridBackDragEnded()
        }
    }

    func noteFolderWallpaper(
        place: WallpaperPathPlace,
        volumeKind: FolderVolumeKind,
        gridClosed: Bool,
        dragActive: Bool
    ) -> FolderExplainerStep {
        explainer.note(place: place, volumeKind: volumeKind, gridClosed: gridClosed, dragActive: dragActive)
    }

    func folderExplainerGridOpened() -> FolderExplainerStep {
        explainer.gridOpened()
    }

    func clearFolderExplainer() -> FolderExplainerStep {
        explainer.clearUnanswered()
    }

    func allowFolderAccess() -> FolderExplainerRecord? {
        guard let record = explainer.allow() else { return nil }
        save()
        return record
    }

    func declineFolderAccess() -> FolderExplainerRecord? {
        guard let record = explainer.notNow() else { return nil }
        save()
        republishFolderLine()
        return record
    }

    /// The deliberate read is about to start. The Settings button waits until it finishes.
    func noteFolderReadStarted() {
        folderAccessBusy = true
    }

    func noteFolderGranted(_ place: WallpaperPathPlace) {
        let before = explainer.granted
        explainer.noteGranted(place)
        if explainer.granted != before {
            save()
        }
        folderAccessBusy = false
        republishFolderLine()
    }

    func noteFolderDenied(_ place: WallpaperPathPlace) {
        let beforeGranted = explainer.granted
        let beforeDenied = explainer.denied
        explainer.noteDenied(place)
        if explainer.granted != beforeGranted || explainer.denied != beforeDenied {
            save()
        }
        folderAccessBusy = false
        republishFolderLine()
    }

    /// Classifies the current wallpaper for the Settings line. This does not open the file.
    func noteFolderSubject(place: WallpaperPathPlace?, volumeKind: FolderVolumeKind) {
        folderAccessPlace = place
        folderAccessVolumeKind = volumeKind
        folderAccessReady = true
        // A read is in flight. Leave the line as it is until that read finishes.
        guard !folderAccessBusy else { return }
        guard let place else {
            folderAccessStatus = .notNeeded
            return
        }
        folderAccessStatus = FolderAccessStatus.make(
            place: place,
            volumeKind: volumeKind,
            asked: explainer.asked.contains(place),
            granted: explainer.granted.contains(place),
            denied: explainer.denied.contains(place),
            lastRead: folderLastRead(for: place)
        )
    }

    /// Not asked shows the existing explainer. The file is still not opened here.
    func requestFolderAllow() {
        guard folderAccessReady, folderAccessStatus == .notAsked, !folderAccessBusy else { return }
        delegate?.gridBackOfferFolderExplainer()
    }

    /// Not now forgets the ask and shows the explainer again. The write is the usual atomic save.
    func requestFolderAskAgain() {
        guard folderAccessReady, !folderAccessBusy, let place = folderAccessPlace else { return }
        let current = FolderAccessLists(
            asked: explainer.askedList,
            granted: explainer.grantedList,
            denied: explainer.deniedList
        )
        let updated = FolderAccessEdits.askAgain(
            place: place,
            volumeKind: folderAccessVolumeKind,
            asked: current.asked,
            granted: current.granted,
            denied: current.denied,
            lastRead: folderLastRead(for: place)
        )
        guard updated != current else { return }
        explainer.replaceLists(asked: updated.asked, granted: updated.granted, denied: updated.denied)
        save()
        republishFolderLine()
        delegate?.gridBackOfferFolderExplainer()
    }

    func openFolderPrivacySettings() {
        delegate?.gridBackOpenPrivacySettings()
    }

    /// Applies a quiet re-check. The path is only the cache key and is not stored on the line.
    func applyFolderRecheck(
        succeeded: Bool,
        place: WallpaperPathPlace,
        path: String,
        denial: FolderDenialCache
    ) -> FolderDenialCache {
        let current = FolderAccessLists(
            asked: explainer.askedList,
            granted: explainer.grantedList,
            denied: explainer.deniedList
        )
        let result = FolderAccessEdits.recheck(
            succeeded: succeeded,
            place: place,
            path: path,
            modified: nil,
            asked: current.asked,
            granted: current.granted,
            denied: current.denied,
            denial: denial
        )
        if result.lists != current {
            explainer.replaceLists(
                asked: result.lists.asked,
                granted: result.lists.granted,
                denied: result.lists.denied
            )
            save()
            republishFolderLine()
        }
        return result.denial
    }

    private func folderLastRead(for place: WallpaperPathPlace) -> FolderReadResult {
        if explainer.denied.contains(place) { return .denied }
        if explainer.granted.contains(place) { return .granted }
        return .unknown
    }

    private func republishFolderLine() {
        guard folderAccessReady else { return }
        noteFolderSubject(place: folderAccessPlace, volumeKind: folderAccessVolumeKind)
    }

    /// The overlay calls this in the same turn it shows the backdrop. Nothing else writes the ink.
    func setInk(_ ink: Ink) {
        guard ink != self.ink else { return }
        self.ink = ink
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        register(shortcut)
        watcher.start(paths: catalog.roots().map(\.path)) { [weak self] in
            self?.rescan()
        }
        rescan()
    }

    func toggleOverlay() {
        if isOverlayVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    func showOverlay() {
        clearDismissedOverlay()
        isOverlayVisible = true
        delegate?.gridBackShowOverlay()
        rescan()
    }

    func hideOverlay() {
        guard isOverlayVisible else { return }
        isOverlayVisible = false
        delegate?.gridBackHideOverlay()
    }

    /// The overlay reports each step of the fade. Search and the open folder stay
    /// until the close has finished, so the fade-out matches what was on screen.
    /// The next open clears them first if that close was reversed.
    func setFadePhase(_ phase: GridFade.Phase) {
        fadePhase = phase
        if phase == .closed {
            clearDismissedOverlay()
        }
    }

    private func clearDismissedOverlay() {
        searchQuery = ""
        selectedResultIndex = 0
        launchError = nil
        closeFolder()
    }

    func showSettings() {
        delegate?.gridBackShowSettings()
    }

    func setSearchQuery(_ text: String) {
        let cleaned = SearchQueryText.cleaned(text)
        guard cleaned != searchQuery else { return }
        searchQuery = cleaned
        selectedResultIndex = 0
        launchError = nil
        if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestCloseFolder()
        }
    }

    /// Command-Q while a GridBack window is key. The first press shows a note.
    /// A second press inside the confirmation window quits. Returns true when
    /// the key event should be swallowed.
    func takeQuitChord(
        characters: String,
        modifiers: KeyModifiers,
        at time: TimeInterval,
        windowIsKey: Bool,
        isRepeat: Bool
    ) -> Bool {
        switch quitConfirmation.decide(
            characters: characters,
            modifiers: modifiers,
            at: time,
            windowIsKey: windowIsKey,
            isRepeat: isRepeat
        ) {
        case .pass:
            return false
        case .swallow:
            return true
        case .arm:
            showQuitNote()
            return true
        case .quit:
            quitNoteTicket += 1
            quitNote = nil
            NSApp.terminate(nil)
            return true
        }
    }

    func selectPage(_ page: Int) {
        guard layout.pages.indices.contains(page) else { return }
        currentPage = page
    }

    func handleKeyDown(keyCode: UInt16, characters: String, modifiers: KeyModifiers) -> Bool {
        guard isOverlayVisible else { return false }
        var drag = heldDrag
        let command = OverlayCommanding.command(
            keyCode: keyCode,
            characters: characters,
            modifiers: modifiers,
            isSearching: isSearching,
            folderIsOpen: openFolderID != nil,
            columns: layout.metrics.columns,
            drag: &drag
        )
        heldDrag = drag
        switch command {
        case .cancelDrag(let cancellation):
            if cancellation.closeTransientFolder {
                requestCloseFolder()
            }
            return true
        case .key(let action):
            return apply(action)
        }
    }

    func beginHeldGridDrag(appID: String) {
        var drag = heldDrag
        drag.beginGrid(appID: appID, origin: layout)
        heldDrag = drag
    }

    func beginHeldFolderDrag(appID: String, folderID: String) {
        var drag = heldDrag
        drag.pickInsideFolder(appID: appID, folderID: folderID, origin: layout)
        heldDrag = drag
    }

    func noteHeldExtracted() {
        var drag = heldDrag
        drag.markExtracted()
        heldDrag = drag
    }

    func beginHeldInsertion(folderID: String, index: Int) {
        var drag = heldDrag
        drag.beginInsertion(folderID: folderID, index: index)
        heldDrag = drag
    }

    func updateHeldInsertion(index: Int) {
        var drag = heldDrag
        drag.updateInsertion(index: index)
        heldDrag = drag
    }

    func leaveHeldInsertion() {
        var drag = heldDrag
        drag.leaveInsertion()
        heldDrag = drag
    }

    func resolveHoverRelease(insideContent: Bool) -> HeldDrag.Outcome {
        var drag = heldDrag
        let outcome = drag.resolveHoverRelease(insideContent: insideContent)
        heldDrag = drag
        return outcome
    }

    func completeHeldDrag() -> HeldDrag.Outcome {
        var drag = heldDrag
        let outcome = drag.complete()
        heldDrag = drag
        return outcome
    }

    private func apply(_ action: SearchKeyAction) -> Bool {
        switch action {
        case .startOrAppend(let text):
            let updated = SearchQueryText.cleaned(searchQuery + text)
            if updated != searchQuery {
                searchQuery = updated
                selectedResultIndex = 0
                launchError = nil
            }
        case .backspace:
            if !searchQuery.isEmpty {
                searchQuery.removeLast()
            }
            selectedResultIndex = 0
        case .clearSearch:
            searchQuery = ""
            selectedResultIndex = 0
        case .dismiss:
            hideOverlay()
        case .closeFolder:
            if folderCloseInFlight {
                closeFolder()
                hideOverlay()
            } else {
                requestCloseFolder()
            }
        case .launchSelected:
            guard searchResults.indices.contains(selectedResultIndex) else { return true }
            launch(id: searchResults[selectedResultIndex].id)
        case .moveSelection(let delta):
            let count = searchResults.count
            guard count > 0 else { return true }
            selectedResultIndex = min(max(0, selectedResultIndex + delta), count - 1)
        case .changePage(let delta):
            guard !layout.pages.isEmpty else { return true }
            currentPage = min(max(0, currentPage + delta), layout.pages.count - 1)
        case .ignored:
            return false
        }
        return true
    }

    func launch(id: String) {
        guard let record = appsByID[id] else {
            showLaunchError(String(localized: "That app is no longer available."))
            return
        }
        launcher.launch(record) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.log.error("Launch failed for \(record.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.showLaunchError(String(localized: "Couldn't open \(record.displayName)."))
                case .success(let launched):
                    if let launched {
                        // Hand the foreground to the app we just opened.
                        // macOS 14+ calls this yieldActivation(to:), then
                        // activate(from:options:) on the launched app.
                        NSApp.yieldActivation(to: launched)
                        _ = launched.activate(from: .current, options: [])
                    }
                    self.hideOverlay()
                }
            }
        }
    }

    func openFolder(_ id: String) {
        guard layout.folder(id) != nil else { return }
        openFolderID = id
    }

    /// Asks the open folder to play its close. The folder view removes itself when that finishes.
    func requestCloseFolder() {
        guard openFolderID != nil else { return }
        guard !folderCloseInFlight else { return }
        folderCloseInFlight = true
        folderCloseRequest += 1
    }

    func closeFolder() {
        openFolderID = nil
        folderCloseInFlight = false
    }

    func group(draggedAppID: String, targetID: String) {
        let previous = layout
        let updated = FolderEditing.group(layout: previous, draggedAppID: draggedAppID, targetID: targetID)
        guard updated != previous else { return }
        layout = updated
        if let created = FolderEditing.createdFolderID(before: previous, after: updated) {
            openFolderID = created
        }
        if let path = updated.indexPath(of: targetID) ?? updated.folders.compactMap({ folder in
            folder.appIDs.contains(draggedAppID) ? updated.indexPath(of: folder.id) : nil
        }).first {
            currentPage = path.page
        }
        save()
    }

    func commitFolderInsert(appID: String, folderID: String, index: Int) {
        let updated = FolderEditing.insertApp(layout: layout, appID: appID, folderID: folderID, at: index)
        guard updated != layout else { return }
        layout = updated
        openFolderID = folderID
        save()
    }

    func returnAppToGrid(_ appID: String) {
        let page = layout.pages.indices.contains(currentPage) ? currentPage : 0
        let slot = layout.pages.indices.contains(page) ? layout.pages[page].count : 0
        let updated = FolderEditing.moveAppOut(layout: layout, appID: appID, toPage: page, toSlot: slot)
        guard updated != layout else { return }
        layout = updated
        if let openFolderID, updated.folder(openFolderID) == nil {
            self.openFolderID = nil
        }
        save()
    }

    func renameFolder(_ id: String, to name: String) {
        let updated = FolderEditing.rename(layout: layout, folderID: id, name: name)
        guard updated != layout else { return }
        layout = updated
        save()
    }

    func commitReorder(_ layout: Layout, page: Int) {
        guard !isSearching else { return }
        if layout != self.layout {
            self.layout = layout
            save()
        }
        selectPage(page)
    }

    func beginShortcutRecording() {
        isRecordingShortcut = true
        shortcutStatus = String(localized: "Press a shortcut. Escape cancels.")
    }

    func cancelShortcutRecording() {
        isRecordingShortcut = false
        shortcutStatus = nil
    }

    func tryAdoptShortcut(_ chord: ShortcutChord) {
        let previous = shortcut
        let previousFailure = hotkeyFailure
        let status = hotkey.register(chord) { [weak self] in
            self?.toggleOverlay()
        }
        guard status == noErr else {
            shortcutStatus = String(localized: "That shortcut couldn't be registered. It may already be used by another app. (Error \(status).)")
            let restored = hotkey.register(previous) { [weak self] in
                self?.toggleOverlay()
            }
            if restored == noErr {
                hotkeyFailure = previousFailure
            } else {
                hotkeyFailure = String(localized: "Shortcut not available (error \(restored)). Use Open GridBack in this menu.")
            }
            return
        }
        shortcut = chord
        hotkeyFailure = nil
        shortcutStatus = nil
        isRecordingShortcut = false
        save()
    }

    func resetShortcutToDefault() {
        tryAdoptShortcut(.default)
    }

    func noteShortcutRejection(_ rejection: ShortcutRejection) {
        switch rejection {
        case .needsModifier:
            shortcutStatus = String(localized: "Include Control, Option, or Command.")
        case .modifierKeyOnly:
            shortcutStatus = String(localized: "Press a letter, number, or function key together with Control, Option, or Command.")
        }
    }

    private func rescan() {
        if scanInFlight {
            scanQueued = true
            return
        }
        scanInFlight = true
        isScanning = appsByID.isEmpty
        let catalog = self.catalog
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let records = catalog.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(records)
                self.scanInFlight = false
                if self.scanQueued {
                    self.scanQueued = false
                    self.rescan()
                }
            }
        }
    }

    private func apply(_ records: [AppRecord]) {
        isScanning = false
        if records.isEmpty && !appsByID.isEmpty {
            persistenceWarning = String(localized: "Couldn't refresh the app list. Showing the last layout.")
            return
        }
        // Keep an app that this scan missed when its bundle is still on disk,
        // so a partial read of an Applications folder does not delete the layout.
        var discovered = records
        var seen = Set(discovered.map(\.id))
        for id in layout.orderedIDs where !seen.contains(id) {
            guard let previous = appsByID[id],
                  FileManager.default.fileExists(atPath: previous.bundlePath) else {
                continue
            }
            discovered.append(previous)
            seen.insert(id)
        }
        let byID = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let updated: Layout
        if hasSavedLayout {
            updated = LayoutEditor.merge(existing: layout, discovered: discovered)
        } else {
            updated = LayoutEditor.freshLayout(apps: discovered, metrics: layout.metrics.clamped)
            hasSavedLayout = true
        }
        appsByID = byID
        if updated != layout {
            layout = updated
            clampPage()
            save()
        }
        refreshIcons(discovered)
        if selectedResultIndex >= searchResults.count {
            selectedResultIndex = 0
        }
    }

    private func refreshIcons(_ records: [AppRecord]) {
        var next: [String: NSImage] = [:]
        next.reserveCapacity(records.count)
        for record in records {
            if let existing = iconImages[record.id] {
                next[record.id] = existing
                continue
            }
            let icon = NSWorkspace.shared.icon(forFile: record.bundlePath)
            icon.size = NSSize(width: 256, height: 256)
            next[record.id] = icon
        }
        iconImages = next
    }

    private func register(_ chord: ShortcutChord) {
        let status = hotkey.register(chord) { [weak self] in
            self?.toggleOverlay()
        }
        if status == noErr {
            hotkeyFailure = nil
        } else {
            hotkeyFailure = String(localized: "Shortcut not available (error \(status)). Use Open GridBack in this menu.")
            log.error("Hotkey registration failed: \(Int(status), privacy: .public)")
        }
    }

    private func save() {
        guard persistEnabled else { return }
        let state = PersistedState(
            layout: layout,
            shortcut: shortcut,
            askedLocations: explainer.askedList,
            grantedLocations: explainer.grantedList,
            deniedLocations: explainer.deniedList
        )
        do {
            try store.save(state)
        } catch {
            persistenceWarning = String(localized: "Couldn't save the layout on this Mac.")
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clampPage() {
        if layout.pages.isEmpty {
            currentPage = 0
        } else if currentPage >= layout.pages.count {
            currentPage = layout.pages.count - 1
        }
    }

    private func showQuitNote() {
        quitNoteTicket += 1
        let ticket = quitNoteTicket
        quitNoteID += 1
        let note = String(localized: "Press ⌘Q again to quit GridBack")
        quitNote = note
        announceQuit(note)
        DispatchQueue.main.asyncAfter(deadline: .now() + QuitConfirmation.window) { [weak self] in
            guard let self, self.quitNoteTicket == ticket else { return }
            self.quitNote = nil
        }
    }

    private func announceQuit(_ note: String) {
        let element: Any = NSApp.keyWindow ?? NSApp!
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: note,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.high.rawValue)
            ]
        )
    }

    private func showLaunchError(_ message: String) {
        launchErrorTicket += 1
        let ticket = launchErrorTicket
        launchError = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.launchErrorTicket == ticket else { return }
            self.launchError = nil
        }
    }

    private static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GridBack", isDirectory: true)
    }

    private enum InitialLoad {
        case loaded(PersistedState)
        case missing
        case failed(String, allowSave: Bool)
    }

    private static func loadInitial(from store: PersistenceStore) -> InitialLoad {
        do {
            if let state = try store.load() {
                return .loaded(state)
            }
            return .missing
        } catch {
            do {
                _ = try store.quarantineStateFile()
                return .failed(
                    String(localized: "The saved layout couldn't be read. GridBack moved that file aside and started a new layout."),
                    allowSave: true
                )
            } catch {
                return .failed(
                    String(localized: "The saved layout couldn't be read. GridBack left the file in place and is using a temporary layout."),
                    allowSave: false
                )
            }
        }
    }
}
