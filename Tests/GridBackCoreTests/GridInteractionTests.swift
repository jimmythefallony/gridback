import XCTest
import GridBackCore

final class GridReorderSessionTests: XCTestCase {
    private let twoByTwo = GridMetrics(columns: 2, rows: 2)

    func testHoveringAnotherSlotShiftsTheNeighbors() {
        var session = GridReorderSession(
            appID: "a",
            layout: Layout(pages: [["a", "b", "c", "d"]], metrics: twoByTwo),
            page: 0
        )
        session.hover(slot: 2, edge: nil)
        XCTAssertEqual(session.preview.pages, [["b", "c", "a", "d"]])
        XCTAssertEqual(session.page, 0)
        XCTAssertEqual(session.preview.orderedIDs.filter { $0 == "a" }.count, 1)
    }

    func testHoveringTheSameSlotDoesNotDuplicateTheIcon() {
        var session = GridReorderSession(
            appID: "a",
            layout: Layout(pages: [["a", "b", "c"]], metrics: twoByTwo),
            page: 0
        )
        session.hover(slot: 0, edge: nil)
        session.hover(slot: 0, edge: nil)
        XCTAssertEqual(session.preview.pages, [["a", "b", "c"]])
    }

    func testScreenEdgeTurnsOnePageUntilThePointerLeaves() {
        var session = GridReorderSession(
            appID: "b",
            layout: Layout(pages: [["a", "b"], ["c", "d"]], metrics: twoByTwo),
            page: 0
        )
        session.hover(slot: nil, edge: .next)
        XCTAssertEqual(session.preview.pages, [["a"], ["b", "c", "d"]])
        XCTAssertEqual(session.page, 1)
        session.hover(slot: nil, edge: .next)
        XCTAssertEqual(session.preview.pages, [["a"], ["b", "c", "d"]])
        session.hover(slot: 2, edge: nil)
        XCTAssertEqual(session.preview.pages, [["a"], ["c", "d", "b"]])
    }

    func testLeftEdgeOnTheFirstPageDoesNothing() {
        var session = GridReorderSession(
            appID: "a",
            layout: Layout(pages: [["a", "b"], ["c"]], metrics: twoByTwo),
            page: 0
        )
        session.hover(slot: nil, edge: .previous)
        XCTAssertEqual(session.preview.pages, [["a", "b"], ["c"]])
        XCTAssertEqual(session.page, 0)
    }

    func testSlotHitTestingAndScreenEdges() {
        XCTAssertEqual(
            GridDragResolver.slot(x: 10, y: 10, cellWidth: 100, cellHeight: 80, columns: 2, rows: 2),
            0
        )
        XCTAssertEqual(
            GridDragResolver.slot(x: 150, y: 90, cellWidth: 100, cellHeight: 80, columns: 2, rows: 2),
            3
        )
        XCTAssertNil(GridDragResolver.slot(x: -1, y: 10, cellWidth: 100, cellHeight: 80, columns: 2, rows: 2))
        XCTAssertEqual(GridDragResolver.pageEdge(x: 10, overlayWidth: 1000), .previous)
        XCTAssertEqual(GridDragResolver.pageEdge(x: 990, overlayWidth: 1000), .next)
        XCTAssertNil(GridDragResolver.pageEdge(x: 500, overlayWidth: 1000))
    }
}

final class PageSwipeTrackerTests: XCTestCase {
    func testRightwardSwipeShowsThePreviousPageOnce() {
        var tracker = PageSwipeTracker(minimumDistance: 50)
        XCTAssertNil(tracker.update(deltaX: 20, deltaY: 0, phase: .began))
        XCTAssertEqual(tracker.update(deltaX: 40, deltaY: 2, phase: .changed), .previous)
        XCTAssertNil(tracker.update(deltaX: 40, deltaY: 0, phase: .changed))
        XCTAssertNil(tracker.update(deltaX: 10, deltaY: 0, phase: .ended))
    }

    func testLeftwardSwipeShowsTheNextPage() {
        var tracker = PageSwipeTracker(minimumDistance: 50)
        XCTAssertEqual(tracker.update(deltaX: -60, deltaY: -5, phase: .changed), .next)
    }

    func testVerticalSwipeDoesNotTurnThePage() {
        var tracker = PageSwipeTracker(minimumDistance: 50)
        XCTAssertNil(tracker.update(deltaX: 10, deltaY: 80, phase: .changed))
        XCTAssertNil(tracker.update(deltaX: 5, deltaY: 10, phase: .ended))
    }

    func testCancelDropsTheGesture() {
        var tracker = PageSwipeTracker(minimumDistance: 50)
        XCTAssertNil(tracker.update(deltaX: 40, deltaY: 0, phase: .began))
        XCTAssertNil(tracker.update(deltaX: 0, deltaY: 0, phase: .cancelled))
        XCTAssertNil(tracker.update(deltaX: 20, deltaY: 0, phase: .changed))
    }
}

final class LaunchGridLayoutTests: XCTestCase {
    func testSideMarginsAreAboutElevenPercentOnALaptopAndALargeDisplay() {
        for width in [1728.0, 2560.0, 3440.0] {
            let layout = LaunchGridLayout.make(overlayWidth: width, overlayHeight: 1117, columns: 7, rows: 5)
            XCTAssertEqual(layout.columns, 7, "width \(width)")
            let fraction = layout.originX / width
            XCTAssertEqual(fraction, 0.11, accuracy: 0.005, "width \(width)")
            XCTAssertEqual(layout.gridWidth / width, 0.78, accuracy: 0.01, "width \(width)")
            XCTAssertEqual(layout.originX, (width - layout.gridWidth) / 2, accuracy: 0.001)
        }
        let laptop = LaunchGridLayout.make(overlayWidth: 1728, overlayHeight: 1117, columns: 7, rows: 5)
        XCTAssertEqual(laptop.topChrome, laptop.bottomChrome)
        XCTAssertLessThan(laptop.iconLabelGap, 6)
    }

    func testHitTestingIgnoresGapsAndMargins() {
        let layout = LaunchGridLayout.make(overlayWidth: 1728, overlayHeight: 1117, columns: 7, rows: 5)
        XCTAssertNil(layout.hitSlot(x: 20, y: layout.originY + 40))
        let slot = 0
        let hitX = layout.originX + layout.columnCenter(slot)
        let hitY = layout.originY + layout.rowCenter(slot)
        XCTAssertEqual(layout.hitSlot(x: hitX, y: hitY), slot)
        let gapX = layout.originX + layout.columnStride - 2
        XCTAssertNil(layout.hitSlot(x: gapX, y: hitY))
    }
}

final class PageSnapTests: XCTestCase {
    func testHalfwayDragSettlesOnTheNextPage() {
        let page = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -600,
            velocityX: 0,
            pageWidth: 1000
        )
        XCTAssertEqual(page, 2)
    }

    func testShortDragWithoutFlickStaysPut() {
        let page = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -200,
            velocityX: 0,
            pageWidth: 1000
        )
        XCTAssertEqual(page, 1)
    }

    func testQuickFlickTurnsThePage() {
        let page = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -80,
            velocityX: -2800,
            pageWidth: 1000
        )
        XCTAssertEqual(page, 2)
    }

    func testRightwardSwipeMovesToThePreviousPage() {
        let page = PageSnap.destination(
            currentPage: 2,
            pageCount: 4,
            translationX: 700,
            velocityX: 0,
            pageWidth: 1000
        )
        XCTAssertEqual(page, 1)
    }

    func testCannotSnapPastTheEnds() {
        XCTAssertEqual(
            PageSnap.destination(currentPage: 0, pageCount: 3, translationX: 900, velocityX: 2000, pageWidth: 1000),
            0
        )
        XCTAssertEqual(
            PageSnap.destination(currentPage: 2, pageCount: 3, translationX: -900, velocityX: -2000, pageWidth: 1000),
            2
        )
    }

    func testRubberBandMovesLessThanTheFinger() {
        let banded = PageSnap.rubberBand(180, dimension: 1000)
        XCTAssertGreaterThan(banded, 0)
        XCTAssertLessThan(banded, 180)
        let visual = PageSnap.visualPage(currentPage: 0, pageCount: 3, translationX: 180, pageWidth: 1000)
        XCTAssertLessThan(visual, 0)
        XCTAssertGreaterThan(visual, -0.2)
    }

    func testMiddleOfTheStripFollowsTheFingerOneToOne() {
        let visual = PageSnap.visualPage(currentPage: 1, pageCount: 4, translationX: -250, pageWidth: 1000)
        XCTAssertEqual(visual, 1.25, accuracy: 0.001)
    }
}
