import Foundation

/// A folder is created only after the pointer rests on another icon.
/// A quick drag still reorders, and a folder cannot be dropped into a folder.
public enum FolderDropDecision: Equatable, Sendable {
    case reorder
    case combine(targetID: String)
}

/// What one drag sample should do. Hovering another icon never reorders:
/// the target stays put so a folder hold can finish. Gaps and empty cells reorder.
public enum DragResolution: Equatable, Sendable {
    case reorder(slot: Int?)
    case hold(targetID: String, armed: Bool)
}

public enum DragArbitration {
    public static func resolve(
        draggedID: String,
        draggedIsFolder: Bool,
        items: [GridItem],
        slot: Int?,
        overIconCenter: Bool,
        dwellSeconds: Double
    ) -> DragResolution {
        if let slot, items.indices.contains(slot) {
            let occupant = items[slot].id
            if occupant != draggedID, !draggedIsFolder {
                let armed = overIconCenter && dwellSeconds >= FolderDrop.dwell
                return .hold(targetID: occupant, armed: armed)
            }
        }
        return .reorder(slot: slot)
    }
}

public enum FolderDrop {
    public static let dwell: Double = 0.5

    public static func decision(
        draggedIsFolder: Bool,
        hoveredID: String?,
        pointerOverIconCenter: Bool,
        dwellSeconds: Double
    ) -> FolderDropDecision {
        guard !draggedIsFolder,
              pointerOverIconCenter,
              let hoveredID,
              dwellSeconds >= dwell else {
            return .reorder
        }
        return .combine(targetID: hoveredID)
    }
}

public struct FolderOpenMetrics: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var iconSide: Double
    public var sideMargin: Double
    public var columns: Int
    public var rows: Int
    public var columnStride: Double
    public var rowStride: Double
}

public struct FolderContainerShape: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var width: Double
    public var height: Double
    public var cornerRadius: Double

    public var aspectRatio: Double {
        guard height > 0 else { return 1 }
        return width / height
    }
}

public struct FolderIconBox: Equatable, Sendable {
    /// Center of the icon in the container's top-left coordinates.
    public var centerX: Double
    public var centerY: Double
    /// Width and height are this same value, so the artwork stays square.
    public var side: Double
}

public enum FolderPanelMetrics {
    public static let openCornerRadius: Double = 28
    public static let tileCornerFactor: Double = 0.22
    public static let verticalPadding: Double = 16

    /// The open folder is as wide as the main icon grid, using that grid's icon size and stride.
    /// Extra apps add rows. If the rows would leave the screen, the row height shrinks and the icon stays square.
    public static func openMetrics(
        gridWidth: Double,
        columns: Int,
        columnStride: Double,
        rowStride: Double,
        iconSide: Double,
        overlayWidth: Double,
        availableHeight: Double,
        appCount: Int
    ) -> FolderOpenMetrics {
        let columns = max(columns, 1)
        let count = max(appCount, 1)
        let rows = (count + columns - 1) / columns
        let fittedWidth = min(max(gridWidth, iconSide + 32), max(overlayWidth - 32, iconSide + 32))
        let usedColumnStride = fittedWidth / Double(columns)
        let limit = max(availableHeight, rowStride + verticalPadding * 2)
        var usedRowStride = max(rowStride, 1)
        var usedIcon = iconSide
        var height = verticalPadding * 2 + Double(rows) * usedRowStride
        if height > limit {
            let inner = max(limit - verticalPadding * 2, 40)
            usedRowStride = inner / Double(rows)
            let scale = min(usedRowStride / max(rowStride, 1), 1)
            usedIcon = max(28, iconSide * scale)
            height = limit
        }
        return FolderOpenMetrics(
            width: fittedWidth,
            height: height,
            iconSide: usedIcon,
            sideMargin: max(0, (overlayWidth - fittedWidth) / 2),
            columns: columns,
            rows: rows,
            columnStride: usedColumnStride,
            rowStride: usedRowStride
        )
    }

    /// Index of the held app inside the open folder. `slotCount` includes that app.
    public static func insertionIndex(localX: Double, localY: Double, slotCount: Int, open: FolderOpenMetrics) -> Int {
        let columns = max(open.columns, 1)
        let slots = max(slotCount, 1)
        let rows = max(1, (slots + columns - 1) / columns)
        let strideX = max(open.columnStride, 1)
        let strideY = max(open.rowStride, 1)
        let rawColumn = localX / strideX
        let column = min(max(Int(rawColumn), 0), columns - 1)
        let columnIndex = min(column + (rawColumn - Double(column) >= 0.5 ? 1 : 0), columns)
        let row = min(max(Int((localY - verticalPadding) / strideY), 0), rows - 1)
        return min(max(row * columns + columnIndex, 0), slots - 1)
    }

    /// Width and height move on their own, so a square becomes a wider rectangle.
    /// Progress is clamped: the ends are exactly the tile and exactly the open panel.
    public static func shape(
        progress: Double,
        tileSide: Double,
        tileCenterX: Double,
        tileCenterY: Double,
        open: FolderOpenMetrics,
        openCenterX: Double,
        openCenterY: Double
    ) -> FolderContainerShape {
        let t = min(max(progress, 0), 1)
        let tileRadius = tileSide * tileCornerFactor
        return FolderContainerShape(
            centerX: tileCenterX + (openCenterX - tileCenterX) * t,
            centerY: tileCenterY + (openCenterY - tileCenterY) * t,
            width: tileSide + (open.width - tileSide) * t,
            height: tileSide + (open.height - tileSide) * t,
            cornerRadius: tileRadius + (openCornerRadius - tileRadius) * t
        )
    }

    /// One side length for the icon. Its box never takes a different width and height.
    public static func iconBox(
        index: Int,
        appCount: Int,
        progress: Double,
        tileSide: Double,
        open: FolderOpenMetrics
    ) -> FolderIconBox {
        let t = min(max(progress, 0), 1)
        let count = max(appCount, 1)
        let mini = tileSide / 3.6
        let miniSpacing = 3.0
        let miniColumns = 3
        let miniIndex = min(max(index, 0), 8)
        let miniColumn = miniIndex % miniColumns
        let miniRow = miniIndex / miniColumns
        let miniGrid = Double(miniColumns) * mini + Double(miniColumns - 1) * miniSpacing
        let miniOrigin = (tileSide - miniGrid) / 2
        let miniX = miniOrigin + Double(miniColumn) * (mini + miniSpacing) + mini / 2
        let miniY = miniOrigin + Double(miniRow) * (mini + miniSpacing) + mini / 2

        let columns = max(open.columns, 1)
        let column = min(max(index, 0), count - 1) % columns
        let row = min(max(index, 0), count - 1) / columns
        let strideX = max(open.columnStride, 1)
        let strideY = max(open.rowStride, 1)
        let openX = (Double(column) + 0.5) * strideX
        let openY = verticalPadding + Double(row) * strideY + open.iconSide / 2
        return FolderIconBox(
            centerX: miniX + (openX - miniX) * t,
            centerY: miniY + (openY - miniY) * t,
            side: mini + (open.iconSide - mini) * t
        )
    }

    /// The app whose square contains the point. Overlapping squares use the closer center.
    /// A miss returns nil so the first app in the folder is not chosen by default.
    public static func hitAppID(
        localX: Double,
        localY: Double,
        ids: [String],
        tileSide: Double,
        open: FolderOpenMetrics,
        progress: Double = 1
    ) -> String? {
        var best: (id: String, distance: Double)?
        for (index, id) in ids.enumerated() {
            let box = iconBox(index: index, appCount: ids.count, progress: progress, tileSide: tileSide, open: open)
            let dx = localX - box.centerX
            let dy = localY - box.centerY
            let half = box.side / 2
            guard abs(dx) <= half, abs(dy) <= half else { continue }
            let distance = dx * dx + dy * dy
            if best == nil || distance < best!.distance {
                best = (id, distance)
            }
        }
        return best?.id
    }
}

public enum FolderHoldOpen {
    public static let duration: Double = 1

    public enum Decision: Equatable, Sendable {
        case idle
        case waiting(targetID: String, elapsed: Double)
        case open(targetID: String)
        case cancelled
    }

    /// Remembers which folder the pointer is resting on. A new target restarts the clock,
    /// so a timer for the previous folder cannot open it.
    public struct Watch: Equatable, Sendable {
        public var targetID: String?
        public var startedAt: TimeInterval?
        public var consumedTargetID: String?
        public init() {}

        public mutating func reset() {
            targetID = nil
            startedAt = nil
            consumedTargetID = nil
        }

        public mutating func sample(now: TimeInterval, targetID: String?, targetIsExistingFolder: Bool) -> Decision {
            guard let targetID, targetIsExistingFolder else {
                let hadTarget = self.targetID != nil
                self.targetID = nil
                self.startedAt = nil
                return hadTarget ? .cancelled : .idle
            }
            if targetID != self.targetID {
                self.targetID = targetID
                self.startedAt = now
                return .waiting(targetID: targetID, elapsed: 0)
            }
            let elapsed = now - (startedAt ?? now)
            if elapsed >= duration, consumedTargetID != targetID {
                consumedTargetID = targetID
                return .open(targetID: targetID)
            }
            return .waiting(targetID: targetID, elapsed: elapsed)
        }
    }
}

/// One in-flight drag. The saved layout stays put until a drop commits it.
/// Escape ends the drag and makes the following mouse-up a no-op.
public struct HeldDrag: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case grid(appID: String)
        case insideFolder(appID: String, folderID: String)
        case extracted(appID: String, folderID: String)
        case inserting(appID: String, folderID: String, index: Int)
    }

    public enum Outcome: Equatable, Sendable {
        case none
        case reorder
        case insert(appID: String, folderID: String, index: Int)
    }

    public struct Cancellation: Equatable, Sendable {
        public var origin: Layout
        public var closeTransientFolder: Bool
    }

    public private(set) var phase: Phase = .idle
    public private(set) var suppressCommit = false
    private var origin: Layout?

    public init() {}

    public var isActive: Bool { phase != .idle }

    public var heldAppID: String? {
        switch phase {
        case .idle:
            return nil
        case .grid(let appID), .insideFolder(let appID, _), .extracted(let appID, _), .inserting(let appID, _, _):
            return appID
        }
    }

    public var originLayout: Layout? { origin }

    public mutating func beginGrid(appID: String, origin: Layout) {
        suppressCommit = false
        self.origin = origin
        phase = .grid(appID: appID)
    }

    public mutating func pickInsideFolder(appID: String, folderID: String, origin: Layout) {
        suppressCommit = false
        self.origin = origin
        phase = .insideFolder(appID: appID, folderID: folderID)
    }

    public mutating func markExtracted() {
        guard case .insideFolder(let appID, let folderID) = phase else { return }
        phase = .extracted(appID: appID, folderID: folderID)
    }

    public mutating func beginInsertion(folderID: String, index: Int) {
        let appID: String
        switch phase {
        case .grid(let id), .extracted(let id, _):
            appID = id
        default:
            return
        }
        phase = .inserting(appID: appID, folderID: folderID, index: index)
    }

    public mutating func updateInsertion(index: Int) {
        guard case .inserting(let appID, let folderID, _) = phase else { return }
        phase = .inserting(appID: appID, folderID: folderID, index: index)
    }

    /// The pointer left the open folder. A later drop is a grid drop, not an insert.
    public mutating func leaveInsertion() {
        guard case .inserting(let appID, _, _) = phase else { return }
        phase = .grid(appID: appID)
    }

    /// Insert only when the pointer is released inside the folder panel.
    /// The tile that kept the folder open, and the margin outside the panel, are not a drop.
    public mutating func resolveHoverRelease(insideContent: Bool) -> Outcome {
        if case .inserting(let appID, _, _) = phase, !insideContent {
            phase = .grid(appID: appID)
        }
        return complete()
    }

    /// Ends the drag without a commit. A later `complete` returns `.none`.
    public mutating func escape() -> Cancellation? {
        guard let origin, phase != .idle else { return nil }
        let closeTransientFolder: Bool
        if case .inserting = phase {
            closeTransientFolder = true
        } else {
            closeTransientFolder = false
        }
        phase = .idle
        suppressCommit = true
        self.origin = nil
        return Cancellation(origin: origin, closeTransientFolder: closeTransientFolder)
    }

    public mutating func complete() -> Outcome {
        if suppressCommit {
            return .none
        }
        if phase == .idle {
            return .none
        }
        let outcome: Outcome
        switch phase {
        case .idle:
            outcome = .none
        case .grid, .extracted:
            outcome = .reorder
        case .insideFolder:
            outcome = .none
        case .inserting(let appID, let folderID, let index):
            outcome = .insert(appID: appID, folderID: folderID, index: index)
        }
        phase = .idle
        origin = nil
        return outcome
    }
}

public enum OverlayCommand: Equatable, Sendable {
    case cancelDrag(HeldDrag.Cancellation)
    case key(SearchKeyAction)
}

public enum OverlayCommanding {
    /// Escape cancels an active drag before search, folder, or grid dismissal.
    public static func command(
        keyCode: UInt16,
        characters: String,
        modifiers: KeyModifiers,
        isSearching: Bool,
        folderIsOpen: Bool,
        columns: Int,
        drag: inout HeldDrag
    ) -> OverlayCommand {
        if keyCode == SearchKeyRouting.escapeKeyCode && !modifiers.isCommandChord, let cancellation = drag.escape() {
            return .cancelDrag(cancellation)
        }
        return .key(
            SearchKeyRouting.action(
                keyCode: keyCode,
                characters: characters,
                modifiers: modifiers,
                isSearching: isSearching,
                columns: columns,
                folderIsOpen: folderIsOpen
            )
        )
    }
}

public enum FolderPanelExit {
    /// The pointer must clear the panel by this many points, so a small move inside does not pull the app out.
    public static let hysteresis: Double = 24

    public static func hasLeft(
        x: Double,
        y: Double,
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        hysteresis: Double = hysteresis
    ) -> Bool {
        x < minX - hysteresis || x > maxX + hysteresis || y < minY - hysteresis || y > maxY + hysteresis
    }
}

public enum FolderInsertionGate {
    /// The folder opens while the pointer is still on the grid tile. The panel then moves
    /// to the middle, so that tile is outside the panel. Staying there is not leaving.
    /// Close only after the pointer is outside the panel and outside that tile.
    public static func shouldClose(
        x: Double,
        y: Double,
        panelReady: Bool,
        panelMinX: Double,
        panelMinY: Double,
        panelMaxX: Double,
        panelMaxY: Double,
        anchorMinX: Double,
        anchorMinY: Double,
        anchorMaxX: Double,
        anchorMaxY: Double
    ) -> Bool {
        guard panelReady else { return false }
        let outsidePanel = FolderPanelExit.hasLeft(
            x: x, y: y,
            minX: panelMinX, minY: panelMinY, maxX: panelMaxX, maxY: panelMaxY
        )
        let outsideTile = FolderPanelExit.hasLeft(
            x: x, y: y,
            minX: anchorMinX, minY: anchorMinY, maxX: anchorMaxX, maxY: anchorMaxY
        )
        return outsidePanel && outsideTile
    }

    /// The panel's own bounds. The source tile and the exit margin are not included.
    public static func isInsideContent(
        x: Double,
        y: Double,
        panelReady: Bool,
        panelMinX: Double,
        panelMinY: Double,
        panelMaxX: Double,
        panelMaxY: Double
    ) -> Bool {
        guard panelReady else { return false }
        return x >= panelMinX && x <= panelMaxX && y >= panelMinY && y <= panelMaxY
    }
}

public enum FolderEditing {
    /// The folder id that `group` created, if this change made a new folder rather than adding to one.
    public static func createdFolderID(before: Layout, after: Layout) -> String? {
        let existing = Set(before.folders.map(\.id))
        return after.folders.first { !existing.contains($0.id) }?.id
    }

    /// Puts the dragged app into a new folder with the target, or into the target folder.
    /// The dragged item must be a loose app. The result never nests folders.
    public static func group(layout: Layout, draggedAppID: String, targetID: String) -> Layout {
        guard draggedAppID != targetID else { return layout }
        guard let draggedPath = layout.indexPath(of: draggedAppID),
              case .app = layout.pages[draggedPath.page][draggedPath.slot] else {
            return layout
        }
        var pages = layout.pages
        pages[draggedPath.page].remove(at: draggedPath.slot)
        if pages[draggedPath.page].isEmpty {
            pages.remove(at: draggedPath.page)
        }
        guard let targetPath = indexPath(of: targetID, in: pages) else { return layout }
        var folders = layout.folders
        switch pages[targetPath.page][targetPath.slot] {
        case .app(let appID):
            let folder = AppFolder(
                id: AppFolder.newID(),
                name: AppFolder.defaultName,
                appIDs: [appID, draggedAppID]
            )
            folders.append(folder)
            pages[targetPath.page][targetPath.slot] = .folder(folder.id)
        case .folder(let folderID):
            guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return layout }
            if !folders[index].appIDs.contains(draggedAppID) {
                folders[index].appIDs.append(draggedAppID)
            }
        }
        return LayoutEditor.repair(Layout(pages: pages, folders: folders, metrics: layout.metrics))
    }

    /// Order the folder would show if `appID` were dropped at `index`. Does not change `existing`.
    public static func previewOrder(existing: [String], appID: String, index: Int) -> [String] {
        var ids = existing.filter { $0 != appID }
        let at = min(max(0, index), ids.count)
        ids.insert(appID, at: at)
        return ids
    }

    /// Moves a loose app into an existing folder at `index`, shifting the apps already there.
    /// The result is unchanged when the folder or the loose app is missing.
    public static func insertApp(layout: Layout, appID: String, folderID: String, at index: Int) -> Layout {
        guard layout.folder(folderID) != nil else { return layout }
        guard let path = layout.indexPath(of: appID),
              case .app = layout.pages[path.page][path.slot] else {
            return layout
        }
        var pages = layout.pages
        pages[path.page].remove(at: path.slot)
        if pages[path.page].isEmpty {
            pages.remove(at: path.page)
        }
        var folders = layout.folders
        for folderIndex in folders.indices {
            folders[folderIndex].appIDs.removeAll { $0 == appID }
        }
        guard let folderIndex = folders.firstIndex(where: { $0.id == folderID }) else { return layout }
        let at = min(max(0, index), folders[folderIndex].appIDs.count)
        folders[folderIndex].appIDs.insert(appID, at: at)
        return LayoutEditor.repair(Layout(pages: pages, folders: folders, metrics: layout.metrics))
    }

    /// Takes an app out of its folder and inserts it on a page. An emptied folder is removed.
    public static func moveAppOut(layout: Layout, appID: String, toPage: Int, toSlot: Int) -> Layout {
        var folders = layout.folders
        var removed = false
        for index in folders.indices {
            if let slot = folders[index].appIDs.firstIndex(of: appID) {
                folders[index].appIDs.remove(at: slot)
                removed = true
            }
        }
        guard removed else { return layout }
        let empty = Set(folders.filter { $0.appIDs.isEmpty }.map(\.id))
        folders.removeAll { $0.appIDs.isEmpty }
        var pages = layout.pages
        for index in pages.indices {
            pages[index].removeAll { item in
                if case .folder(let id) = item { return empty.contains(id) }
                return false
            }
        }
        pages.removeAll { $0.isEmpty }
        let destination = min(max(0, toPage), pages.count)
        if destination == pages.count {
            pages.append([])
        }
        let slot = min(max(0, toSlot), pages[destination].count)
        pages[destination].insert(.app(appID), at: slot)
        return LayoutEditor.repair(Layout(pages: pages, folders: folders, metrics: layout.metrics))
    }

    public static func rename(layout: Layout, folderID: String, name: String) -> Layout {
        guard let index = layout.folders.firstIndex(where: { $0.id == folderID }) else { return layout }
        var layout = layout
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        layout.folders[index].name = trimmed.isEmpty ? AppFolder.defaultName : String(trimmed.prefix(80))
        return layout
    }

    private static func indexPath(of id: String, in pages: [[GridItem]]) -> (page: Int, slot: Int)? {
        for (pageIndex, page) in pages.enumerated() {
            if let slot = page.firstIndex(where: { $0.id == id }) {
                return (pageIndex, slot)
            }
        }
        return nil
    }
}
