import Foundation

/// Ordering rules:
/// - A fresh layout sorts by display name and fills pages front to back.
/// - After that, new apps are appended. Existing order is not re-sorted.
/// - Removing an app closes the gap on its own page only. An emptied folder is removed.
/// - A drag places the tile at a slot on a page. Overflow spills forward.
/// - An empty page is dropped. Later pages are not pulled backward to refill
///   a short page.
public enum LayoutEditor {
    public static func freshLayout(apps: [AppRecord], metrics: GridMetrics) -> Layout {
        let metrics = metrics.clamped
        let ids = uniqueIDs(in: NameOrder.sorted(apps).map(\.id))
        return Layout(pages: paginate(ids.map(GridItem.app), capacity: metrics.capacity), metrics: metrics)
    }

    public static func merge(existing: Layout, discovered: [AppRecord]) -> Layout {
        let metrics = existing.metrics.clamped
        let valid = Set(discovered.map(\.id))
        let kept = keeping(pages: existing.pages, folders: existing.folders, validApps: valid, metrics: metrics)
        var pages = kept.pages
        var seen = Set(kept.orderedIDs)
        let newcomers = NameOrder.sorted(discovered.filter { !seen.contains($0.id) })
        for app in newcomers {
            if pages.isEmpty || pages[pages.count - 1].count >= metrics.capacity {
                pages.append([])
            }
            pages[pages.count - 1].append(.app(app.id))
            seen.insert(app.id)
        }
        return Layout(pages: pages, folders: kept.folders, metrics: metrics)
    }

    /// `toSlot` is the index the tile should occupy on `toPage` after it has
    /// left its previous slot. Pass the page's count to append.
    public static func move(layout: Layout, appID: String, toPage: Int, toSlot: Int) -> Layout {
        let metrics = layout.metrics.clamped
        var pages = layout.pages
        guard let source = indexPath(of: appID, in: pages) else {
            return Layout(pages: pages, folders: layout.folders, metrics: metrics)
        }

        if source.page == toPage {
            var page = pages[source.page]
            let item = page.remove(at: source.slot)
            let slot = min(max(0, toSlot), page.count)
            page.insert(item, at: slot)
            pages[source.page] = page
            return Layout(pages: pages, folders: layout.folders, metrics: metrics)
        }

        let moving = pages[source.page][source.slot]
        pages[source.page].remove(at: source.slot)
        var destination = toPage
        if pages[source.page].isEmpty {
            pages.remove(at: source.page)
            if source.page < destination {
                destination -= 1
            }
        }

        if destination < 0 {
            destination = 0
        }
        if destination > pages.count {
            destination = pages.count
        }
        if destination == pages.count {
            pages.append([])
        }

        let slot = min(max(0, toSlot), pages[destination].count)
        pages[destination].insert(moving, at: slot)
        pages = spill(pages, capacity: metrics.capacity)
        pages.removeAll { $0.isEmpty }
        return Layout(pages: pages, folders: layout.folders, metrics: metrics)
    }

    /// Drops blank ids and duplicate apps (first placement wins), spills an
    /// over-full page forward, and drops empty pages and empty folders.
    public static func repair(_ layout: Layout) -> Layout {
        keeping(pages: layout.pages, folders: layout.folders, validApps: nil, metrics: layout.metrics.clamped)
    }

    /// Slot that keeps a dropped tile on this page: the end when there is room,
    /// otherwise the last occupied slot so the previous last tile spills forward.
    public static func slotThatStaysOnPage(itemCount: Int, capacity: Int) -> Int {
        let capacity = max(capacity, 1)
        if itemCount < capacity {
            return itemCount
        }
        return capacity - 1
    }

    private static func keeping(
        pages sourcePages: [[GridItem]],
        folders sourceFolders: [AppFolder],
        validApps: Set<String>?,
        metrics: GridMetrics
    ) -> Layout {
        let metrics = metrics.clamped
        let foldersByID = Dictionary(sourceFolders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seenApps = Set<String>()
        var seenFolders = Set<String>()
        var pages: [[GridItem]] = []
        var folders: [AppFolder] = []
        for page in sourcePages {
            var kept: [GridItem] = []
            for item in page {
                switch item {
                case .app(let raw):
                    let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty, validApps?.contains(id) != false, seenApps.insert(id).inserted else { continue }
                    kept.append(.app(id))
                case .folder(let raw):
                    let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !id.isEmpty, seenFolders.insert(id).inserted, var folder = foldersByID[id] else { continue }
                    var apps: [String] = []
                    for rawApp in folder.appIDs {
                        let appID = rawApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !appID.isEmpty, validApps?.contains(appID) != false, seenApps.insert(appID).inserted else { continue }
                        apps.append(appID)
                    }
                    guard !apps.isEmpty else { continue }
                    folder.appIDs = apps
                    let trimmed = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    folder.name = trimmed.isEmpty ? AppFolder.defaultName : String(trimmed.prefix(80))
                    folders.append(folder)
                    kept.append(.folder(id))
                }
            }
            if !kept.isEmpty {
                pages.append(kept)
            }
        }
        return Layout(pages: spill(pages, capacity: metrics.capacity), folders: folders, metrics: metrics)
    }

    private static func paginate(_ items: [GridItem], capacity: Int) -> [[GridItem]] {
        guard capacity > 0, !items.isEmpty else { return [] }
        var pages: [[GridItem]] = []
        var index = 0
        while index < items.count {
            let end = min(index + capacity, items.count)
            pages.append(Array(items[index..<end]))
            index = end
        }
        return pages
    }

    private static func spill(_ pages: [[GridItem]], capacity: Int) -> [[GridItem]] {
        guard capacity > 0 else { return pages }
        var pages = pages
        var index = 0
        while index < pages.count {
            if pages[index].count > capacity {
                let overflow = Array(pages[index].suffix(pages[index].count - capacity))
                pages[index] = Array(pages[index].prefix(capacity))
                if index + 1 == pages.count {
                    pages.append([])
                }
                pages[index + 1].insert(contentsOf: overflow, at: 0)
            }
            index += 1
        }
        pages.removeAll { $0.isEmpty }
        return pages
    }

    private static func uniqueIDs(in ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
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
