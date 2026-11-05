import Foundation

/// Where a pointer is while an icon is being dragged inside the grid.
public enum GridDragPointer: Equatable, Sendable {
    /// A cell on the page currently showing. The slot may be past the last icon.
    case slot(Int)
    case previousPage
    case nextPage
}

/// Decides which grid cell or screen edge a pointer is over.
/// Coordinates are in points, origin at the top-left.
public enum GridDragResolver {
    /// How close to the left or right of the overlay counts as the screen edge.
    public static let edgeMargin: Double = 48

    public static func slot(
        x: Double,
        y: Double,
        cellWidth: Double,
        cellHeight: Double,
        columns: Int,
        rows: Int
    ) -> Int? {
        guard cellWidth > 0, cellHeight > 0, columns > 0, rows > 0 else { return nil }
        let width = cellWidth * Double(columns)
        let height = cellHeight * Double(rows)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let column = min(Int(x / cellWidth), columns - 1)
        let row = min(Int(y / cellHeight), rows - 1)
        return row * columns + column
    }

    /// `x` is the pointer's distance from the left of the full overlay.
    /// `leading` and `trailing` are edges already covered by the Dock, so the
    /// page-turn zone starts just inside the usable area.
    public static func pageEdge(
        x: Double,
        overlayWidth: Double,
        margin: Double = edgeMargin,
        leading: Double = 0,
        trailing: Double = 0
    ) -> PageTurn? {
        let leading = max(0, leading)
        let trailing = max(0, trailing)
        guard overlayWidth > leading + trailing + margin * 2, margin > 0 else { return nil }
        if x <= leading + margin { return .previous }
        if x >= overlayWidth - trailing - margin { return .next }
        return nil
    }
}

/// One in-grid drag. The preview is what the other icons do while the finger is down.
/// Nothing here talks to the pasteboard, so the Dock never sees the drag.
public struct GridReorderSession: Equatable, Sendable {
    public let appID: String
    public private(set) var preview: Layout
    public private(set) var page: Int
    private var edgeLatch: PageTurn?

    public init(appID: String, layout: Layout, page: Int) {
        self.appID = appID
        self.preview = layout
        let last = max(layout.pages.count - 1, 0)
        self.page = min(max(0, page), last)
        self.edgeLatch = nil
    }

    /// `edge` wins over `slot` so the screen edge turns the page instead of
    /// dropping into the first or last column.
    public mutating func hover(slot: Int?, edge: PageTurn?) {
        if let edge {
            guard edgeLatch != edge else { return }
            edgeLatch = edge
            switch edge {
            case .previous:
                turn(by: -1)
            case .next:
                turn(by: 1)
            }
            return
        }
        edgeLatch = nil
        guard let slot, preview.pages.indices.contains(page) else { return }
        if let path = preview.indexPath(of: appID), path.page == page, path.slot == slot {
            return
        }
        let updated = LayoutEditor.move(layout: preview, appID: appID, toPage: page, toSlot: slot)
        preview = updated
        if let landed = updated.indexPath(of: appID) {
            page = landed.page
        }
    }

    private mutating func turn(by delta: Int) {
        let destination = page + delta
        guard destination >= 0 else { return }
        let slot: Int
        if destination < preview.pages.count {
            if delta < 0 {
                slot = LayoutEditor.slotThatStaysOnPage(
                    itemCount: preview.pages[destination].count,
                    capacity: preview.metrics.capacity
                )
            } else {
                slot = 0
            }
        } else if delta > 0 {
            slot = 0
        } else {
            return
        }
        let updated = LayoutEditor.move(layout: preview, appID: appID, toPage: destination, toSlot: slot)
        preview = updated
        if let landed = updated.indexPath(of: appID) {
            page = landed.page
        }
    }
}
