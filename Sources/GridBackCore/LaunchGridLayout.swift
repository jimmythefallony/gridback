import Foundation

/// Where the icon grid sits on the overlay, and which icon a point hits.
///
/// The grid stays centered. Gaps between icons are not part of an icon's hit
/// area, so moving the pointer through a gap does not highlight anything.
public struct LaunchGridLayout: Equatable, Sendable {
    public var columns: Int
    public var rows: Int
    public var iconSide: Double
    public var labelHeight: Double
    public var iconLabelGap: Double
    public var hitWidth: Double
    public var columnStride: Double
    public var rowStride: Double
    public var originX: Double
    public var originY: Double
    /// Full screen width. Each page is this wide; `originX` is padding inside the page.
    public var pageWidth: Double
    public var gridWidth: Double
    public var gridHeight: Double
    public var topChrome: Double
    public var bottomChrome: Double
    /// Horizontal center of the area not reserved by the Dock or menu bar.
    public var contentCenterX: Double
    public var searchCenterY: Double
    public var pageControlCenterY: Double

    public var contentHeight: Double {
        iconSide + iconLabelGap + labelHeight
    }

    public static func make(
        overlayWidth: Double,
        overlayHeight: Double,
        columns: Int,
        rows: Int,
        reserve: ScreenReserve = .none
    ) -> LaunchGridLayout {
        let columns = max(columns, 1)
        let rows = max(rows, 1)
        let reservedTop = max(0, reserve.top)
        let reservedLeft = max(0, reserve.left)
        let reservedBottom = max(0, reserve.bottom)
        let reservedRight = max(0, reserve.right)
        // The 108pt chrome clears the search pill and the page controls.
        // A visible Dock or menu bar pushes that chrome out past the reserved edge.
        let topChrome = max(108, reservedTop + 80)
        let bottomChrome = max(108, reservedBottom + 80)
        let usableWidth = max(overlayWidth - reservedLeft - reservedRight, 1)
        // About 9% of the usable width on each side. The rest is the icon area,
        // and that padding lives inside each full-width page.
        let sideMargin = usableWidth * 0.09
        let gridWidth = max(usableWidth - sideMargin * 2, 1)
        let columnStride = gridWidth / Double(columns)
        var iconSide = min(112, max(64, columnStride * 0.58))
        var rowStride = max(iconSide + 40, min(168, columnStride * 0.92))
        let availableHeight = max(overlayHeight - topChrome - bottomChrome, 1)
        if rowStride * Double(rows) > availableHeight {
            rowStride = availableHeight / Double(rows)
            iconSide = min(iconSide, max(56, rowStride * 0.62))
        }
        let gridHeight = rowStride * Double(rows)
        let originX = reservedLeft + (usableWidth - gridWidth) / 2
        let originY = topChrome + max(0, (availableHeight - gridHeight) / 2)
        let hitWidth = min(columnStride - 16, iconSide + 36)
        let labelHeight = min(28, max(16, rowStride - iconSide - 6))
        return LaunchGridLayout(
            columns: columns,
            rows: rows,
            iconSide: iconSide,
            labelHeight: labelHeight,
            iconLabelGap: 3,
            hitWidth: max(iconSide, hitWidth),
            columnStride: columnStride,
            rowStride: rowStride,
            originX: originX,
            originY: originY,
            pageWidth: overlayWidth,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            topChrome: topChrome,
            bottomChrome: bottomChrome,
            contentCenterX: reservedLeft + usableWidth / 2,
            searchCenterY: max(58, reservedTop + 36),
            pageControlCenterY: overlayHeight - max(58, reservedBottom + 36)
        )
    }

    /// Slot under a point in overlay coordinates, or nil when the point is in a
    /// gap, a margin, or outside the icon and its label.
    public func hitSlot(x: Double, y: Double) -> Int? {
        let localX = x - originX
        let localY = y - originY
        guard localX >= 0, localY >= 0, localX < gridWidth, localY < gridHeight else { return nil }
        let column = min(Int(localX / columnStride), columns - 1)
        let row = min(Int(localY / rowStride), rows - 1)
        let cellX = localX - Double(column) * columnStride
        let cellY = localY - Double(row) * rowStride
        let contentWidth = min(hitWidth, columnStride)
        let contentHeight = min(self.contentHeight + 8, rowStride)
        let contentX = (columnStride - contentWidth) / 2
        let contentY = (rowStride - contentHeight) / 2
        guard cellX >= contentX, cellX <= contentX + contentWidth else { return nil }
        guard cellY >= contentY, cellY <= contentY + contentHeight else { return nil }
        return row * columns + column
    }

    /// The pointer is over the icon artwork, not the label or the gap around the cell.
    public func isOverIconCenter(x: Double, y: Double, slot: Int) -> Bool {
        guard slot >= 0, columns > 0 else { return false }
        let centerX = originX + columnCenter(slot)
        let centerY = originY + rowCenter(slot) - (labelHeight + iconLabelGap) / 2
        let dx = x - centerX
        let dy = y - centerY
        let radius = iconSide * 0.5
        return dx * dx + dy * dy <= radius * radius
    }

    public func columnCenter(_ slot: Int) -> Double {
        let column = slot % columns
        return (Double(column) + 0.5) * columnStride
    }

    public func rowCenter(_ slot: Int) -> Double {
        let row = slot / columns
        return (Double(row) + 0.5) * rowStride
    }
}
