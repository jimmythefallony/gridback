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
        XCTAssertEqual(GridDragResolver.pageEdge(x: 200, overlayWidth: 1000, leading: 180), .previous)
        XCTAssertNil(GridDragResolver.pageEdge(x: 200, overlayWidth: 1000, leading: 0))
        XCTAssertEqual(GridDragResolver.pageEdge(x: 820, overlayWidth: 1000, trailing: 160), .next)
        XCTAssertNil(GridDragResolver.pageEdge(x: 820, overlayWidth: 1000, trailing: 0))
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

final class ScreenReserveTests: XCTestCase {
    func testBottomDockAndMenuBar() {
        let reserve = ScreenReserve.occupying(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            visibleX: 0, visibleY: 80, visibleWidth: 1728, visibleHeight: 1117 - 80 - 25
        )
        XCTAssertEqual(reserve.bottom, 80, accuracy: 0.001)
        XCTAssertEqual(reserve.top, 25, accuracy: 0.001)
        XCTAssertEqual(reserve.left, 0, accuracy: 0.001)
        XCTAssertEqual(reserve.right, 0, accuracy: 0.001)
    }

    func testLeftAndRightDock() {
        let left = ScreenReserve.occupying(
            screenX: 0, screenY: 0, screenWidth: 1440, screenHeight: 900,
            visibleX: 150, visibleY: 0, visibleWidth: 1440 - 150, visibleHeight: 870
        )
        XCTAssertEqual(left.left, 150, accuracy: 0.001)
        XCTAssertEqual(left.top, 30, accuracy: 0.001)
        XCTAssertEqual(left.bottom, 0, accuracy: 0.001)

        let right = ScreenReserve.occupying(
            screenX: 100, screenY: 0, screenWidth: 1440, screenHeight: 900,
            visibleX: 100, visibleY: 0, visibleWidth: 1440 - 160, visibleHeight: 875
        )
        XCTAssertEqual(right.right, 160, accuracy: 0.001)
        XCTAssertEqual(right.left, 0, accuracy: 0.001)
    }

    func testSystemLauncherIsNotTheIdleDockHost() {
        let idleDock = SystemLauncherWindow(
            owner: "Dock",
            name: "",
            memoryBytes: 2432,
            width: 1728,
            height: 1117
        )
        XCTAssertFalse(SystemLauncherVisibility.isVisible(
            frontmostBundleID: "com.brave.Browser.beta",
            launcherProcessRunning: false,
            windows: [idleDock],
            screenWidth: 1728,
            screenHeight: 1117
        ))
        XCTAssertFalse(SystemLauncherVisibility.isVisible(
            frontmostBundleID: SystemLauncherVisibility.dockBundleID,
            launcherProcessRunning: false,
            windows: [idleDock],
            screenWidth: 1728,
            screenHeight: 1117
        ))
    }

    func testSystemLauncherIsVisibleWhenItHasANameOrBackingStore() {
        let named = SystemLauncherWindow(owner: "Dock", name: "Launchpad", memoryBytes: 2432, width: 800, height: 600)
        XCTAssertTrue(SystemLauncherVisibility.isVisible(
            frontmostBundleID: "com.apple.finder",
            launcherProcessRunning: false,
            windows: [named],
            screenWidth: 1728,
            screenHeight: 1117
        ))
        let drawn = SystemLauncherWindow(owner: "Dock", name: "", memoryBytes: 2_000_000, width: 1728, height: 1117)
        XCTAssertTrue(SystemLauncherVisibility.isVisible(
            frontmostBundleID: "com.apple.finder",
            launcherProcessRunning: false,
            windows: [drawn],
            screenWidth: 1728,
            screenHeight: 1117
        ))
        XCTAssertTrue(SystemLauncherVisibility.isVisible(
            frontmostBundleID: "com.apple.finder",
            launcherProcessRunning: true,
            windows: [],
            screenWidth: 1728,
            screenHeight: 1117
        ))
        let apps = SystemLauncherWindow(owner: "Apps", name: "", memoryBytes: 100, width: 200, height: 200)
        XCTAssertTrue(SystemLauncherVisibility.isVisible(
            frontmostBundleID: nil,
            launcherProcessRunning: false,
            windows: [apps],
            screenWidth: 1728,
            screenHeight: 1117
        ))
    }

    func testMenuBarReservesSpaceOnlyWhenTheTopInsetIsReal() {
        XCTAssertFalse(ScreenReserve.none.menuBarReservesSpace)
        XCTAssertFalse(ScreenReserve(top: 0, left: 0, bottom: 90, right: 0).menuBarReservesSpace)
        XCTAssertTrue(ScreenReserve(top: 33, left: 0, bottom: 90, right: 0).menuBarReservesSpace)
    }

    func testAutoHideDoesNotReserveADockEdge() {
        let reserve = ScreenReserve.occupying(
            screenX: 0, screenY: 0, screenWidth: 1512, screenHeight: 982,
            visibleX: 0, visibleY: 0, visibleWidth: 1512, visibleHeight: 982 - 32
        )
        XCTAssertEqual(reserve, ScreenReserve(top: 32, left: 0, bottom: 0, right: 0))
    }
}

final class MenuBarPresentationTests: XCTestCase {
    func testAutoHiddenMenuBarDoesNotAddADockHideFlag() {
        let hidden = MenuBarPresentation.keepingDockVisible(current: 0, suppressAutoHiddenMenuBar: true)
        XCTAssertEqual(hidden, MenuBarPresentation.autoHideMenuBar)
        XCTAssertEqual(hidden & MenuBarPresentation.hideDock, 0)
        XCTAssertEqual(hidden & MenuBarPresentation.autoHideDock, 0)
        XCTAssertEqual(hidden & MenuBarPresentation.hideMenuBar, 0)
    }

    func testVisibleMenuBarLeavesPresentationUntouched() {
        XCTAssertEqual(MenuBarPresentation.keepingDockVisible(current: 0, suppressAutoHiddenMenuBar: false), 0)
        let dockAlreadyAutoHides = MenuBarPresentation.autoHideDock
        XCTAssertEqual(
            MenuBarPresentation.keepingDockVisible(current: dockAlreadyAutoHides, suppressAutoHiddenMenuBar: false),
            dockAlreadyAutoHides
        )
    }

    func testExistingDockFlagIsNotIntroducedByMenuBarSuppression() {
        let combined = MenuBarPresentation.keepingDockVisible(current: 0, suppressAutoHiddenMenuBar: true)
        XCTAssertFalse(combined & MenuBarPresentation.hideDock != 0)
        let alreadyHidden = MenuBarPresentation.hideDock
        let kept = MenuBarPresentation.keepingDockVisible(current: alreadyHidden, suppressAutoHiddenMenuBar: true)
        XCTAssertEqual(kept & MenuBarPresentation.hideDock, MenuBarPresentation.hideDock)
        XCTAssertEqual(kept & MenuBarPresentation.autoHideMenuBar, MenuBarPresentation.autoHideMenuBar)
    }
}

final class GridOverlayLayoutTests: XCTestCase {
    func testBottomDockWindowCoversTheMenuBarAndStopsAtTheDock() {
        let frames = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: DockOcclusion(edge: .bottom, thickness: 90)
        )
        XCTAssertEqual(frames.grid.x, 0, accuracy: 0.001)
        XCTAssertEqual(frames.grid.y, 90, accuracy: 0.001)
        XCTAssertEqual(frames.grid.width, 1728, accuracy: 0.001)
        XCTAssertEqual(frames.grid.height, 1027, accuracy: 0.001)
        XCTAssertEqual(frames.grid.y + frames.grid.height, 1117, accuracy: 0.001)
        XCTAssertEqual(frames.backdrop, PlacedRect(x: 0, y: 0, width: 1728, height: 1117))
        let placed = BackdropImagePlacement.inWindow(screen: frames.backdrop, window: frames.grid)
        XCTAssertEqual(placed.x, 0, accuracy: 0.001)
        XCTAssertEqual(placed.y, -90, accuracy: 0.001)
        XCTAssertEqual(placed.width, 1728, accuracy: 0.001)
        XCTAssertEqual(placed.height, 1117, accuracy: 0.001)
    }

    func testLeftAndRightDocksMirrorTheExcludedBand() {
        let left = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: DockOcclusion(edge: .left, thickness: 80)
        )
        XCTAssertEqual(left.grid, PlacedRect(x: 80, y: 0, width: 1648, height: 1117))
        let right = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: DockOcclusion(edge: .right, thickness: 70)
        )
        XCTAssertEqual(right.grid, PlacedRect(x: 0, y: 0, width: 1658, height: 1117))
    }

    func testAutoHideReservesADockEdgeWhenVisibleFrameDoesNot() {
        XCTAssertEqual(DockOcclusion.autoHideThickness(tileSize: 64), 90, accuracy: 0.001)
        let reserve = ScreenReserve(top: 33, left: 0, bottom: 0, right: 0)
        let occlusion = DockOcclusion.resolve(
            reserve: reserve,
            autoHides: true,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: DockOcclusion.autoHideThickness(tileSize: 64),
            magnificationOverflow: 0,
            scale: 2
        )
        XCTAssertEqual(occlusion.edge, .bottom)
        XCTAssertEqual(occlusion.thickness, 90, accuracy: 0.001)
        let frames = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: occlusion
        )
        XCTAssertEqual(frames.grid.y, 90, accuracy: 0.001)
        XCTAssertEqual(frames.grid.y + frames.grid.height, 1117, accuracy: 0.001)
    }

    func testVisibleDockInsetWinsAndMagnificationExtendsIt() {
        let reserve = ScreenReserve(top: 33, left: 0, bottom: 90, right: 0)
        let resting = DockOcclusion.resolve(
            reserve: reserve,
            autoHides: true,
            autoHideEdge: .left,
            estimatedAutoHideThickness: 40,
            magnificationOverflow: DockOcclusion.magnificationOverflow(enabled: false, tileSize: 64, largeSize: 128),
            scale: 2
        )
        XCTAssertEqual(resting.edge, .bottom)
        XCTAssertEqual(resting.thickness, 90, accuracy: 0.001)
        let magnified = DockOcclusion.resolve(
            reserve: reserve,
            autoHides: false,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: 0,
            magnificationOverflow: DockOcclusion.magnificationOverflow(enabled: true, tileSize: 64, largeSize: 128),
            scale: 2
        )
        let label = DockOcclusion.magnifiedLabelHeight + DockOcclusion.magnifiedLabelMargin
        XCTAssertEqual(magnified.thickness, 90 + (128 - 64) + label, accuracy: 0.001)
        let frames = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: magnified
        )
        XCTAssertEqual(frames.grid.y, magnified.thickness, accuracy: 0.001)
        XCTAssertGreaterThan(frames.grid.y, 90)
    }

    func testMagnifiedBandIncludesTheHoverLabel() {
        let label = DockOcclusion.magnifiedLabelHeight + DockOcclusion.magnifiedLabelMargin
        XCTAssertGreaterThanOrEqual(DockOcclusion.magnifiedLabelHeight, 22)
        XCTAssertLessThanOrEqual(DockOcclusion.magnifiedLabelHeight, 30)
        XCTAssertGreaterThan(DockOcclusion.magnifiedLabelMargin, 0)
        let overflow = DockOcclusion.magnificationOverflow(enabled: true, tileSize: 64, largeSize: 128)
        XCTAssertEqual(overflow, (128 - 64) + label, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(90 + overflow, 128 + label)

        let autoHide = DockOcclusion.resolve(
            reserve: ScreenReserve(top: 0, left: 0, bottom: 0, right: 0),
            autoHides: true,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: DockOcclusion.autoHideThickness(tileSize: 64),
            magnificationOverflow: overflow,
            scale: 2
        )
        XCTAssertEqual(autoHide.edge, .bottom)
        XCTAssertEqual(autoHide.thickness, 90 + overflow, accuracy: 0.001)

        let showing = DockOcclusion.resolve(
            reserve: ScreenReserve(top: 33, left: 0, bottom: 90, right: 0),
            autoHides: false,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: 0,
            magnificationOverflow: overflow,
            scale: 2
        )
        XCTAssertEqual(showing.thickness, autoHide.thickness, accuracy: 0.001)

        let leftOverflow = DockOcclusion.magnificationOverflow(enabled: true, tileSize: 48, largeSize: 96)
        let left = DockOcclusion.resolve(
            reserve: ScreenReserve(top: 33, left: 80, bottom: 0, right: 0),
            autoHides: false,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: 0,
            magnificationOverflow: leftOverflow,
            scale: 2
        )
        XCTAssertEqual(left.edge, .left)
        XCTAssertEqual(left.thickness, 80 + (96 - 48) + label, accuracy: 0.001)

        let right = DockOcclusion.resolve(
            reserve: ScreenReserve(top: 33, left: 0, bottom: 0, right: 70),
            autoHides: true,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: 90,
            magnificationOverflow: overflow,
            scale: 2
        )
        XCTAssertEqual(right.edge, .right)
        XCTAssertEqual(right.thickness, 70 + overflow, accuracy: 0.001)

        let frames = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: autoHide
        )
        XCTAssertEqual(frames.backdrop, PlacedRect(x: 0, y: 0, width: 1728, height: 1117))
        XCTAssertEqual(frames.grid.y, autoHide.thickness, accuracy: 0.001)
        let layout = LaunchGridLayout.make(
            overlayWidth: frames.grid.width,
            overlayHeight: frames.grid.height,
            columns: 7,
            rows: 5
        )
        XCTAssertGreaterThan(layout.pageControlCenterY, 0)
        XCTAssertLessThan(layout.pageControlCenterY, frames.grid.height)
        XCTAssertLessThanOrEqual(layout.originY + layout.gridHeight, frames.grid.height)
    }

    func testNoDockLeavesOneFullScreenGrid() {
        let occlusion = DockOcclusion.resolve(
            reserve: ScreenReserve(top: 33, left: 0, bottom: 0, right: 0),
            autoHides: false,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: 90,
            magnificationOverflow: 0,
            scale: 2
        )
        XCTAssertEqual(occlusion.thickness, 0, accuracy: 0.001)
        let frames = GridOverlayFrames.make(
            screenX: 0, screenY: 0, screenWidth: 1728, screenHeight: 1117,
            occlusion: occlusion
        )
        XCTAssertEqual(frames.grid, frames.backdrop)
    }
}

final class MenuBarSuppressionTests: XCTestCase {
    func testRevealedAutoHideBarIsStillSuppressed() {
        XCTAssertTrue(MenuBarSuppression.shouldSuppress(menuBarReservesSpace: true, userAutoHidesMenuBar: true))
        XCTAssertTrue(MenuBarSuppression.shouldSuppress(menuBarReservesSpace: false, userAutoHidesMenuBar: false))
        XCTAssertFalse(MenuBarSuppression.shouldSuppress(menuBarReservesSpace: true, userAutoHidesMenuBar: false))
    }
}

final class LaunchGridLayoutTests: XCTestCase {
    func testSideMarginsAreAboutNinePercentAndEachPageIsFullWidth() {
        for width in [1728.0, 2560.0, 3440.0] {
            let layout = LaunchGridLayout.make(overlayWidth: width, overlayHeight: 1117, columns: 7, rows: 5)
            XCTAssertEqual(layout.columns, 7, "width \(width)")
            XCTAssertEqual(layout.pageWidth, width, accuracy: 0.001, "width \(width)")
            let fraction = layout.originX / width
            XCTAssertEqual(fraction, 0.09, accuracy: 0.005, "width \(width)")
            XCTAssertEqual(layout.gridWidth / width, 0.82, accuracy: 0.01, "width \(width)")
            XCTAssertEqual(layout.originX, (width - layout.gridWidth) / 2, accuracy: 0.001)
        }
        let laptop = LaunchGridLayout.make(overlayWidth: 1728, overlayHeight: 1117, columns: 7, rows: 5)
        XCTAssertEqual(laptop.topChrome, laptop.bottomChrome)
        XCTAssertLessThan(laptop.iconLabelGap, 6)
        XCTAssertEqual(laptop.searchCenterY, 58, accuracy: 0.001)
        XCTAssertEqual(laptop.pageControlCenterY, 1117 - 58, accuracy: 0.001)
        XCTAssertEqual(laptop.contentCenterX, 1728 / 2, accuracy: 0.001)
    }

    func testVisibleDockInsetsKeepIconsOutOfTheReservedEdge() {
        let bottom = ScreenReserve(top: 24, left: 0, bottom: 96, right: 0)
        let layout = LaunchGridLayout.make(
            overlayWidth: 1728,
            overlayHeight: 1117,
            columns: 7,
            rows: 5,
            reserve: bottom
        )
        XCTAssertGreaterThanOrEqual(layout.bottomChrome, 96 + 80)
        XCTAssertLessThanOrEqual(layout.originY + layout.gridHeight, 1117 - 96)
        XCTAssertGreaterThanOrEqual(layout.pageControlCenterY, 0)
        XCTAssertLessThan(layout.pageControlCenterY, 1117 - 96)
        XCTAssertGreaterThan(layout.searchCenterY, 24)

        let left = ScreenReserve(top: 0, left: 200, bottom: 0, right: 0)
        let shifted = LaunchGridLayout.make(
            overlayWidth: 1728,
            overlayHeight: 1117,
            columns: 7,
            rows: 5,
            reserve: left
        )
        XCTAssertGreaterThanOrEqual(shifted.originX, 200)
        XCTAssertLessThanOrEqual(shifted.originX + shifted.gridWidth, 1728)

        let right = ScreenReserve(top: 0, left: 0, bottom: 0, right: 180)
        let rightDock = LaunchGridLayout.make(
            overlayWidth: 1728,
            overlayHeight: 1117,
            columns: 7,
            rows: 5,
            reserve: right
        )
        XCTAssertLessThanOrEqual(rightDock.originX + rightDock.gridWidth, 1728 - 180)
        XCTAssertEqual(rightDock.bottomChrome, 108, accuracy: 0.001)
    }

    func testAutoHideLeavesTheFullGridArea() {
        let hidden = ScreenReserve(top: 24, left: 0, bottom: 0, right: 0)
        let layout = LaunchGridLayout.make(
            overlayWidth: 1728,
            overlayHeight: 1117,
            columns: 7,
            rows: 5,
            reserve: hidden
        )
        let plain = LaunchGridLayout.make(overlayWidth: 1728, overlayHeight: 1117, columns: 7, rows: 5)
        XCTAssertEqual(layout.bottomChrome, plain.bottomChrome, accuracy: 0.001)
        XCTAssertEqual(layout.originX, plain.originX, accuracy: 0.001)
        XCTAssertEqual(layout.pageControlCenterY, plain.pageControlCenterY, accuracy: 0.001)
    }

    func testAutoHiddenMenuBarLeavesTheTopAtFullHeight() {
        let hiddenBar = ScreenReserve(top: 0, left: 0, bottom: 90, right: 0)
        let layout = LaunchGridLayout.make(
            overlayWidth: 1728,
            overlayHeight: 1117,
            columns: 7,
            rows: 5,
            reserve: hiddenBar
        )
        let plain = LaunchGridLayout.make(overlayWidth: 1728, overlayHeight: 1117, columns: 7, rows: 5)
        XCTAssertFalse(hiddenBar.menuBarReservesSpace)
        XCTAssertEqual(layout.topChrome, plain.topChrome, accuracy: 0.001)
        XCTAssertEqual(layout.searchCenterY, plain.searchCenterY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(layout.bottomChrome, 90 + 80)
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
