import AppKit
import Foundation
import GridBackCore
import os

protocol GridBackUIDelegate: AnyObject {
    func gridBackShowOverlay()
    func gridBackHideOverlay()
    func gridBackShowSettings()
}

/// Main-thread coordinator for the menu bar, overlay, catalog, and saved layout.
final class GridBackModel: ObservableObject {
    static let shared = GridBackModel()

    @Published private(set) var layout: Layout
    @Published private(set) var appsByID: [String: AppRecord] = [:]
    @Published private(set) var searchQuery = ""
    @Published private(set) var currentPage = 0
    @Published private(set) var openFolderID: String?
    @Published private(set) var selectedResultIndex = 0
    @Published private(set) var isOverlayVisible = false
    @Published private(set) var launchError: String?
    @Published private(set) var shortcut: ShortcutChord
    @Published var heldDrag = HeldDrag()
    private var escapePump: Timer?
    @Published private(set) var hotkeyFailure: String?
    @Published private(set) var persistenceWarning: String?
    @Published private(set) var isRecordingShortcut = false
    @Published private(set) var shortcutStatus: String?
    @Published private(set) var isScanning = true
    @Published private(set) var iconImages: [String: NSImage] = [:]
    /// Menu bar and Dock space taken from the screen's visible frame. Zero on
    /// an edge means that edge is not reserved, including an auto-hidden Dock.
    @Published private(set) var screenReserve = ScreenReserve.none

    weak var delegate: GridBackUIDelegate?

    private let store: PersistenceStore
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
        searchQuery = ""
        selectedResultIndex = 0
        launchError = nil
        openFolderID = nil
        isOverlayVisible = true
        delegate?.gridBackShowOverlay()
        rescan()
    }

    func hideOverlay() {
        guard isOverlayVisible else { return }
        isOverlayVisible = false
        searchQuery = ""
        launchError = nil
        openFolderID = nil
        delegate?.gridBackHideOverlay()
    }

    func showSettings() {
        delegate?.gridBackShowSettings()
    }

    func setSearchQuery(_ text: String) {
        guard text != searchQuery else { return }
        searchQuery = text
        selectedResultIndex = 0
        launchError = nil
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            openFolderID = nil
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
            stopEscapePump()
            if cancellation.closeTransientFolder {
                closeFolder()
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
        startEscapePump()
    }

    func beginHeldFolderDrag(appID: String, folderID: String) {
        var drag = heldDrag
        drag.pickInsideFolder(appID: appID, folderID: folderID, origin: layout)
        heldDrag = drag
        startEscapePump()
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

    func completeHeldDrag() -> HeldDrag.Outcome {
        stopEscapePump()
        var drag = heldDrag
        let outcome = drag.complete()
        heldDrag = drag
        return outcome
    }

    /// While a drag is tracking, SwiftUI only pulls mouse events, so the normal
    /// key monitor never sees Escape. This timer runs in the tracking run loop
    /// and takes a queued Escape before the mouse-up can save the drag.
    private func startEscapePump() {
        guard escapePump == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.pullQueuedEscape()
        }
        RunLoop.main.add(timer, forMode: .common)
        escapePump = timer
    }

    private func stopEscapePump() {
        escapePump?.invalidate()
        escapePump = nil
    }

    private func pullQueuedEscape() {
        guard heldDrag.isActive else {
            stopEscapePump()
            return
        }
        let modes: [RunLoop.Mode] = [.eventTracking, .default, .modalPanel, .common]
        for mode in modes {
            guard let waiting = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: mode, dequeue: false),
                  waiting.keyCode == SearchKeyRouting.escapeKeyCode else {
                continue
            }
            let modifiers = KeyModifiers(eventFlags: waiting.modifierFlags)
            guard !modifiers.isCommandChord else { continue }
            guard let event = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: mode, dequeue: true) else {
                return
            }
            _ = handleKeyDown(
                keyCode: event.keyCode,
                characters: event.characters ?? "",
                modifiers: KeyModifiers(eventFlags: event.modifierFlags)
            )
            return
        }
    }

    private func apply(_ action: SearchKeyAction) -> Bool {
        switch action {
        case .startOrAppend(let text):
            searchQuery.append(text)
            selectedResultIndex = 0
            launchError = nil
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
            closeFolder()
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

    func closeFolder() {
        openFolderID = nil
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
        let state = PersistedState(layout: layout, shortcut: shortcut)
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
