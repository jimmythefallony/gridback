import Foundation

/// How many icons fit on one page. Classic grid is 7 columns by 5 rows.
public struct GridMetrics: Codable, Equatable, Sendable {
    public static let minimumCount = 1
    public static let maximumCount = 12

    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }

    public static let classic = GridMetrics(columns: 7, rows: 5)

    public var capacity: Int {
        let clamped = self.clamped
        return clamped.columns * clamped.rows
    }

    public var clamped: GridMetrics {
        GridMetrics(
            columns: min(max(columns, Self.minimumCount), Self.maximumCount),
            rows: min(max(rows, Self.minimumCount), Self.maximumCount)
        )
    }
}
