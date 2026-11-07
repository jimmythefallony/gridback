import Foundation

/// A folder is created only after the pointer rests on another icon.
/// A quick drag still reorders, and a folder cannot be dropped into a folder.
public enum FolderDropDecision: Equatable, Sendable {
    case reorder
    case combine(targetID: String)
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

public enum FolderEditing {
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
