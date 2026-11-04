import Foundation

/// Pages of app ids. A page never borrows icons from the next page to fill
/// itself, so a short page can sit in front of a later page.
public struct Layout: Codable, Equatable, Sendable {
    public var pages: [[String]]
    public var metrics: GridMetrics

    public init(pages: [[String]], metrics: GridMetrics) {
        self.pages = pages
        self.metrics = metrics
    }

    public func indexPath(of id: String) -> (page: Int, slot: Int)? {
        for (pageIndex, page) in pages.enumerated() {
            if let slot = page.firstIndex(of: id) {
                return (pageIndex, slot)
            }
        }
        return nil
    }

    public var orderedIDs: [String] {
        pages.flatMap { $0 }
    }
}
