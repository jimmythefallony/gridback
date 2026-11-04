import XCTest
import GridBackCore

final class LayoutEditorTests: XCTestCase {
    private let twoByTwo = GridMetrics(columns: 2, rows: 2)

    func testFreshLayoutSortsByDisplayNameAndPaginates() {
        let apps = [
            app("Zoom", "com.zoom"),
            app("apple", "com.apple"),
            app("Banana", "com.banana"),
            app("App 10", "com.ten"),
            app("App 2", "com.two"),
            app("App 1", "com.one")
        ]
        let layout = LayoutEditor.freshLayout(apps: apps, metrics: twoByTwo)
        XCTAssertEqual(layout.metrics, twoByTwo)
        XCTAssertEqual(
            layout.pages,
            [
                ["com.one", "com.two", "com.ten", "com.apple"],
                ["com.banana", "com.zoom"]
            ]
        )
    }

    func testFreshLayoutTieBreaksOnIdentifier() {
        let apps = [
            app("Mail", "com.z"),
            app("mail", "com.a")
        ]
        let layout = LayoutEditor.freshLayout(apps: apps, metrics: .classic)
        XCTAssertEqual(layout.orderedIDs, ["com.a", "com.z"])
    }

    func testFreshLayoutDropsDuplicateIdentifiers() {
        let apps = [
            app("One", "com.one"),
            app("One Copy", "com.one")
        ]
        let layout = LayoutEditor.freshLayout(apps: apps, metrics: .classic)
        XCTAssertEqual(layout.orderedIDs, ["com.one"])
    }

    func testMergeKeepsOrderDropsMissingAndDoesNotPullLaterPages() {
        let existing = Layout(
            pages: [
                ["a", "b", "c"],
                ["d", "e"]
            ],
            metrics: twoByTwo
        )
        let discovered = [
            app("C", "c"),
            app("A", "a"),
            app("E", "e"),
            app("D", "d")
        ]
        let merged = LayoutEditor.merge(existing: existing, discovered: discovered)
        XCTAssertEqual(merged.pages, [["a", "c"], ["d", "e"]])
    }

    func testMergeRemovesAnEmptyPageWithoutRefillingFromTheNextPage() {
        let existing = Layout(
            pages: [["a"], ["d", "e"]],
            metrics: twoByTwo
        )
        let merged = LayoutEditor.merge(
            existing: existing,
            discovered: [app("D", "d"), app("E", "e")]
        )
        XCTAssertEqual(merged.pages, [["d", "e"]])
    }

    func testMergeAppendsNewAppsAtTheEndWithoutResorting() {
        let existing = Layout(
            pages: [["zoom", "apple"], ["delta"]],
            metrics: twoByTwo
        )
        let discovered = [
            app("Zoom", "zoom"),
            app("apple", "apple"),
            app("delta", "delta"),
            app("Banana", "banana"),
            app("alpha", "alpha")
        ]
        let merged = LayoutEditor.merge(existing: existing, discovered: discovered)
        XCTAssertEqual(
            merged.pages,
            [
                ["zoom", "apple"],
                ["delta", "alpha", "banana"]
            ]
        )
    }

    func testMergeStartsANewPageWhenTheLastPageIsFull() {
        let existing = Layout(
            pages: [["a", "b", "c", "d"]],
            metrics: twoByTwo
        )
        let merged = LayoutEditor.merge(
            existing: existing,
            discovered: [app("A", "a"), app("B", "b"), app("C", "c"), app("D", "d"), app("E", "e")]
        )
        XCTAssertEqual(merged.pages, [["a", "b", "c", "d"], ["e"]])
    }

    func testSamePageMoveUsesTheFinalSlot() {
        let layout = Layout(pages: [["a", "b", "c", "d"]], metrics: twoByTwo)
        let moved = LayoutEditor.move(layout: layout, appID: "a", toPage: 0, toSlot: 2)
        XCTAssertEqual(moved.pages, [["b", "c", "a", "d"]])
    }

    func testMoveAcrossPagesCompactsTheSourceAndSpillsForward() {
        let layout = Layout(
            pages: [
                ["a", "b", "c"],
                ["d", "e", "f", "g"]
            ],
            metrics: twoByTwo
        )
        let moved = LayoutEditor.move(layout: layout, appID: "b", toPage: 1, toSlot: 0)
        XCTAssertEqual(
            moved.pages,
            [
                ["a", "c"],
                ["b", "d", "e", "f"],
                ["g"]
            ]
        )
    }

    func testMoveOntoAFullPreviousPagePushesTheLastItemForward() {
        let layout = Layout(
            pages: [
                ["a", "b", "c", "d"],
                ["e"]
            ],
            metrics: twoByTwo
        )
        let slot = LayoutEditor.slotThatStaysOnPage(itemCount: 4, capacity: 4)
        let moved = LayoutEditor.move(layout: layout, appID: "e", toPage: 0, toSlot: slot)
        XCTAssertEqual(moved.pages, [["a", "b", "c", "e"], ["d"]])
    }

    func testMoveDoesNotCreateASecondCopy() {
        let layout = Layout(pages: [["a", "b"], ["c"]], metrics: twoByTwo)
        let moved = LayoutEditor.move(layout: layout, appID: "a", toPage: 1, toSlot: 0)
        XCTAssertEqual(moved.orderedIDs.filter { $0 == "a" }.count, 1)
        XCTAssertEqual(moved.pages, [["b"], ["a", "c"]])
    }

    func testMovingUnknownAppLeavesTheLayoutAlone() {
        let layout = Layout(pages: [["a"]], metrics: .classic)
        XCTAssertEqual(LayoutEditor.move(layout: layout, appID: "missing", toPage: 0, toSlot: 0), Layout(pages: [["a"]], metrics: .classic))
    }

    func testRepairDropsDuplicatesAndSpillsWithoutResorting() {
        let broken = Layout(
            pages: [
                ["a", "b", "a", ""],
                ["c", "b", "d", "e", "f"]
            ],
            metrics: twoByTwo
        )
        let repaired = LayoutEditor.repair(broken)
        XCTAssertEqual(
            repaired.pages,
            [
                ["a", "b"],
                ["c", "d", "e", "f"]
            ]
        )
    }

    func testClassicCapacityIsThirtyFive() {
        XCTAssertEqual(GridMetrics.classic.capacity, 35)
    }

    private func app(_ name: String, _ id: String) -> AppRecord {
        AppRecord(bundleIdentifier: id, bundlePath: "/Applications/\(name).app", displayName: name)
    }
}
