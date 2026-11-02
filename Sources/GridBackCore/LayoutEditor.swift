import Foundation

/// Ordering rules for v0.1:
/// - A fresh layout sorts by display name and fills pages front to back.
/// - After that, new apps are appended. Existing order is not re-sorted.
/// - Removing an app closes the gap on its own page only.
/// - A drag places the app at a slot on a page. Overflow spills forward.
/// - An empty page is dropped. Later pages are not pulled backward to refill
///   a short page.
public enum LayoutEditor {
    public static func freshLayout(apps: [AppRecord], metrics: GridMetrics) -> Layout {
        let metrics = metrics.clamped
        let ids = uniqueIDs(in: NameOrder.sorted(apps).map(\.id))
        return Layout(pages: paginate(ids, capacity: metrics.capacity), metrics: metrics)
    }

    public static func merge(existing: Layout, discovered: [AppRecord]) -> Layout {
        let metrics = existing.metrics.clamped
        let valid = Set(discovered.map(\.id))
        var seen = Set<String>()
        var pages: [[String]] = []
        for page in existing.pages {
            var kept: [String] = []
            for id in page where valid.contains(id) && seen.insert(id).inserted {
                kept.append(id)
            }
            if !kept.isEmpty {
                pages.append(kept)
            }
        }
        pages = spill(pages, capacity: metrics.capacity)

        let placed = Set(pages.flatMap { $0 })
        let newcomers = NameOrder.sorted(discovered.filter { !placed.contains($0.id) })
        for app in newcomers {
            if pages.isEmpty || pages[pages.count - 1].count >= metrics.capacity {
                pages.append([])
            }
            pages[pages.count - 1].append(app.id)
        }
        return Layout(pages: pages, metrics: metrics)
    }

    /// `toSlot` is the index the app should occupy on `toPage` after it has
    /// left its previous slot. Pass the page's count to append.
    public static func move(layout: Layout, appID: String, toPage: Int, toSlot: Int) -> Layout {
        let metrics = layout.metrics.clamped
        var pages = layout.pages
        guard let source = indexPath(of: appID, in: pages) else {
            return Layout(pages: pages, metrics: metrics)
        }

        if source.page == toPage {
            var page = pages[source.page]
            let item = page.remove(at: source.slot)
            let slot = min(max(0, toSlot), page.count)
            page.insert(item, at: slot)
            pages[source.page] = page
            return Layout(pages: pages, metrics: metrics)
        }

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
        pages[destination].insert(appID, at: slot)
        pages = spill(pages, capacity: metrics.capacity)
        pages.removeAll { $0.isEmpty }
        return Layout(pages: pages, metrics: metrics)
    }

    /// Drops blank ids and duplicate ids (first placement wins), spills an
    /// over-full page forward, and drops empty pages. Does not re-sort.
    public static func repair(_ layout: Layout) -> Layout {
        let metrics = layout.metrics.clamped
        var seen = Set<String>()
        var pages: [[String]] = []
        for page in layout.pages {
            var kept: [String] = []
            for raw in page {
                let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, seen.insert(id).inserted else { continue }
                kept.append(id)
            }
            if !kept.isEmpty {
                pages.append(kept)
            }
        }
        return Layout(pages: spill(pages, capacity: metrics.capacity), metrics: metrics)
    }

    /// Slot that keeps a dropped app on this page: the end when there is room,
    /// otherwise the last occupied slot so the previous last app spills forward.
    public static func slotThatStaysOnPage(itemCount: Int, capacity: Int) -> Int {
        let capacity = max(capacity, 1)
        if itemCount < capacity {
            return itemCount
        }
        return capacity - 1
    }

    private static func paginate(_ ids: [String], capacity: Int) -> [[String]] {
        guard capacity > 0, !ids.isEmpty else { return [] }
        var pages: [[String]] = []
        var index = 0
        while index < ids.count {
            let end = min(index + capacity, ids.count)
            pages.append(Array(ids[index..<end]))
            index = end
        }
        return pages
    }

    private static func spill(_ pages: [[String]], capacity: Int) -> [[String]] {
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

    private static func indexPath(of id: String, in pages: [[String]]) -> (page: Int, slot: Int)? {
        for (pageIndex, page) in pages.enumerated() {
            if let slot = page.firstIndex(of: id) {
                return (pageIndex, slot)
            }
        }
        return nil
    }
}
