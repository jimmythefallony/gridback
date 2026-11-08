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
    /// The open panel stops growing well before the edges of the overlay.
    public static let maxWidth: Double = 460
    /// At least this fraction of the overlay stays wallpaper on each side.
    public static let sideMarginFraction: Double = 0.24
    public static let openCornerRadius: Double = 28
    public static let tileCornerFactor: Double = 0.22
    public static let padding: Double = 28
    public static let iconGap: Double = 18
    public static let labelBlock: Double = 40
    public static let rowGap: Double = 16

    public static func openWidth(overlayWidth: Double) -> Double {
        let available = max(overlayWidth * (1 - sideMarginFraction * 2), 180)
        return min(maxWidth, available)
    }

    public static func sideMargin(overlayWidth: Double) -> Double {
        max(0, (overlayWidth - openWidth(overlayWidth: overlayWidth)) / 2)
    }

    public static func openMetrics(overlayWidth: Double, preferredIcon: Double, appCount: Int) -> FolderOpenMetrics {
        let count = max(appCount, 1)
        let columns = min(count, 4)
        let rows = (count + columns - 1) / columns
        let width = openWidth(overlayWidth: overlayWidth)
        let inner = max(width - padding * 2, 36)
        let gaps = iconGap * Double(max(columns - 1, 0))
        let fitted = (inner - gaps) / Double(columns)
        let icon = min(max(preferredIcon, 36), max(fitted, 36))
        let height = padding * 2
            + Double(rows) * (icon + labelBlock)
            + Double(max(rows - 1, 0)) * rowGap
        return FolderOpenMetrics(
            width: width,
            height: height,
            iconSide: icon,
            sideMargin: sideMargin(overlayWidth: overlayWidth),
            columns: columns
        )
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

        let columns = open.columns
        let rows = (count + columns - 1) / columns
        let column = min(max(index, 0), count - 1) % columns
        let row = min(max(index, 0), count - 1) / columns
        let rowWidth = Double(columns) * open.iconSide + Double(max(columns - 1, 0)) * iconGap
        let originX = (open.width - rowWidth) / 2
        let openX = originX + Double(column) * (open.iconSide + iconGap) + open.iconSide / 2
        let block = open.iconSide + labelBlock
        let contentHeight = Double(rows) * block + Double(max(rows - 1, 0)) * rowGap
        let originY = (open.height - contentHeight) / 2
        let openY = originY + Double(row) * (block + rowGap) + open.iconSide / 2
        return FolderIconBox(
            centerX: miniX + (openX - miniX) * t,
            centerY: miniY + (openY - miniY) * t,
            side: mini + (open.iconSide - mini) * t
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
