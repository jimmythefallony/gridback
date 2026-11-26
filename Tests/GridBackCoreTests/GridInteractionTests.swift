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

final class PicturePreparationTests: XCTestCase {
    func testStaleRenderIsNotApplied() {
        XCTAssertTrue(PictureApplyGate.shouldApply(
            completedGeneration: 3,
            completedCacheKey: "wall|3456x2234",
            currentGeneration: 3,
            currentCacheKey: "wall|3456x2234",
            stillWanted: true
        ))
        XCTAssertFalse(PictureApplyGate.shouldApply(
            completedGeneration: 3,
            completedCacheKey: "wall|3456x2234",
            currentGeneration: 4,
            currentCacheKey: "wall|3456x2234",
            stillWanted: true
        ))
        XCTAssertFalse(PictureApplyGate.shouldApply(
            completedGeneration: 3,
            completedCacheKey: "wall|3456x2234",
            currentGeneration: 3,
            currentCacheKey: "other|3456x2234",
            stillWanted: true
        ))
        XCTAssertFalse(PictureApplyGate.shouldApply(
            completedGeneration: 3,
            completedCacheKey: "wall|3456x2234",
            currentGeneration: 3,
            currentCacheKey: "wall|3456x2234",
            stillWanted: false
        ))
    }

    func testMissingWallpaperStillOpensWithThePlainBlurAndIsNotKept() {
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: false,
                completedGeneration: 2,
                completedCacheKey: "",
                currentGeneration: 2,
                currentCacheKey: "",
                stillWanted: true
            ),
            .plainBlur
        )
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: false,
                completedGeneration: 2,
                completedCacheKey: "missing|100x100",
                currentGeneration: 2,
                currentCacheKey: "missing|100x100",
                stillWanted: true
            ),
            .plainBlur
        )
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: false,
                completedGeneration: 2,
                completedCacheKey: "missing|100x100",
                currentGeneration: 3,
                currentCacheKey: "missing|100x100",
                stillWanted: true
            ),
            .ignore
        )
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: false,
                completedGeneration: 2,
                completedCacheKey: "",
                currentGeneration: 2,
                currentCacheKey: "",
                stillWanted: false
            ),
            .ignore
        )
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: true,
                completedGeneration: 2,
                completedCacheKey: "pictures|100x100",
                currentGeneration: 2,
                currentCacheKey: "pictures|100x100",
                stillWanted: true
            ),
            .picture
        )
    }

    func testBoxKernelsStayOddAndMatchTheRetinaBlur() {
        let tiny = GaussianBoxKernel.sizes(sigma: 0, passes: 3)
        XCTAssertEqual(tiny, [1, 1, 1])
        let retina = GaussianBoxKernel.sizes(sigma: 104, passes: 3)
        XCTAssertEqual(retina.count, 3)
        XCTAssertTrue(retina.allSatisfy { $0 >= 1 && $0 % 2 == 1 })
        XCTAssertGreaterThan(retina.max() ?? 0, 1)
    }

    func testBlurUsesAQuarterOfTheScreenAndTheSameScaleForTheRadius() {
        let size = WallpaperRenderSize.make(pixelWidth: 3200, pixelHeight: 2000, pointHeight: 1000)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 500)
        XCTAssertEqual(size.maxPixelSize, 800)
        let fullSigma = WallpaperRenderSize.pointRadius * 2000 / 1000
        XCTAssertEqual(size.sigma, fullSigma / Double(WallpaperRenderSize.downscale), accuracy: 0.0001)

        let odd = WallpaperRenderSize.make(pixelWidth: 1001, pixelHeight: 503, pointHeight: 400)
        XCTAssertEqual(odd.width, 250)
        XCTAssertEqual(odd.height, 125)
        XCTAssertEqual(odd.maxPixelSize, 250)
        XCTAssertEqual(odd.sigma, WallpaperRenderSize.pointRadius * 125 / 400, accuracy: 0.0001)
    }

    func testBlurSizeNeverDropsBelowOnePixel() {
        let size = WallpaperRenderSize.make(pixelWidth: 1, pixelHeight: 2, pointHeight: 0)
        XCTAssertEqual(size.width, 1)
        XCTAssertEqual(size.height, 1)
        XCTAssertEqual(size.maxPixelSize, 1)
        XCTAssertEqual(size.sigma, WallpaperRenderSize.pointRadius)
    }

    func testPictureWorkLeavesTheMainThreadAndAppliesBackOnIt() {
        let finished = expectation(description: "applied on main")
        var workWasOnMain: Bool?
        OffMainWork.start {
            workWasOnMain = Thread.isMainThread
            return "ready"
        } apply: { value in
            XCTAssertEqual(value, "ready")
            XCTAssertEqual(workWasOnMain, false)
            XCTAssertTrue(Thread.isMainThread)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
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

    func testMissingLargeSizeUsesTheDefaultMagnifiedSize() {
        XCTAssertEqual(DockOcclusion.largeSize(stored: nil, magnificationEnabled: true), 128, accuracy: 0.001)
        XCTAssertEqual(DockOcclusion.largeSize(stored: 96, magnificationEnabled: true), 96, accuracy: 0.001)
        XCTAssertEqual(DockOcclusion.largeSize(stored: nil, magnificationEnabled: false), 0, accuracy: 0.001)
        let overflow = DockOcclusion.magnificationOverflow(
            enabled: true,
            tileSize: 64,
            largeSize: DockOcclusion.largeSize(stored: nil, magnificationEnabled: true)
        )
        let band = DockOcclusion.resolve(
            reserve: ScreenReserve(top: 0, left: 0, bottom: 0, right: 0),
            autoHides: true,
            autoHideEdge: .bottom,
            estimatedAutoHideThickness: DockOcclusion.autoHideThickness(tileSize: 64),
            magnificationOverflow: overflow,
            scale: 2
        )
        XCTAssertEqual(band.thickness, 194, accuracy: 0.001)
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
        // Halfway is past the 20% line, so the page still turns exactly once.
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
        // 15% of the page, released with no speed, snaps back.
        let page = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -150,
            velocityX: 0,
            pageWidth: 1000
        )
        XCTAssertEqual(page, 1)
    }

    func testDragOfTwentyPercentTurnsOnePage() {
        let width = 1000.0
        let page = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -PageSnap.commitDistanceFraction * width,
            velocityX: 0,
            pageWidth: width
        )
        XCTAssertEqual(page, 2)
    }

    func testQuickFlickTurnsThePage() {
        let page = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -40,
            velocityX: -400,
            pageWidth: 1000
        )
        XCTAssertEqual(page, 2)
    }

    func testReversedFlickCancelsTheTurn() {
        let cancelled = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -400,
            velocityX: 400,
            pageWidth: 1000
        )
        XCTAssertEqual(cancelled, 1)
        let slowDriftBack = PageSnap.destination(
            currentPage: 1,
            pageCount: 4,
            translationX: -400,
            velocityX: 100,
            pageWidth: 1000
        )
        XCTAssertEqual(slowDriftBack, 2)
    }

    func testFastFlickNeverSkipsAPage() {
        XCTAssertEqual(
            PageSnap.destination(currentPage: 3, pageCount: 20, translationX: -40, velocityX: -5000, pageWidth: 200),
            4
        )
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
            PageSnap.destination(currentPage: 0, pageCount: 5, translationX: 800, velocityX: 5000, pageWidth: 1000),
            0
        )
        XCTAssertEqual(
            PageSnap.destination(currentPage: 4, pageCount: 5, translationX: -800, velocityX: -5000, pageWidth: 1000),
            4
        )
    }

    func testWindowedVelocityIgnoresStationaryAndOldSamples() {
        var tracker = PageDragTracker()
        tracker.add(deltaX: 100, deltaY: 0, time: 0)
        tracker.add(deltaX: 30, deltaY: 0, time: 1.00)
        tracker.add(deltaX: 0, deltaY: 0, time: 1.02)
        tracker.add(deltaX: 30, deltaY: 0, time: 1.04)
        tracker.add(deltaX: 0, deltaY: 0, time: 1.06)
        XCTAssertEqual(tracker.velocityX(), 750, accuracy: 0.001)

        var paused = PageDragTracker()
        paused.add(deltaX: 30, deltaY: 0, time: 1.00)
        paused.add(deltaX: 30, deltaY: 0, time: 1.04)
        paused.add(deltaX: 0, deltaY: 0, time: 1.04 + PageDragTracker.velocityWindow + 0.05)
        XCTAssertEqual(paused.velocityX(), 0, accuracy: 0.001)
    }

    func testAVerticalDragIsNotMostlyHorizontal() {
        var tracker = PageDragTracker()
        tracker.add(deltaX: 12, deltaY: 80, time: 1)
        tracker.add(deltaX: 8, deltaY: 40, time: 1.04)
        XCTAssertFalse(tracker.isMostlyHorizontal)
    }

    func testSettleInitialVelocityNormalisesSignCapAndNearZero() {
        XCTAssertEqual(
            PageSnap.settleInitialVelocity(pagesPerSecond: 2, remainingPages: 0.5, pageWidth: 1000),
            4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PageSnap.settleInitialVelocity(pagesPerSecond: -2, remainingPages: -0.5, pageWidth: 1000),
            4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PageSnap.settleInitialVelocity(pagesPerSecond: -2, remainingPages: 0.5, pageWidth: 1000),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PageSnap.settleInitialVelocity(pagesPerSecond: 100, remainingPages: 0.25, pageWidth: 1000),
            PageSnap.settleVelocityCap,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PageSnap.settleInitialVelocity(pagesPerSecond: 5, remainingPages: 0.0005, pageWidth: 1000),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            PageSnap.settleInitialVelocity(pagesPerSecond: 5, remainingPages: 0, pageWidth: 1000),
            0,
            accuracy: 0.001
        )
    }

    func testSwipeStartingBetweenPagesFollowsFromThere() {
        let visual = PageSnap.visualPage(currentPage: 1.4, pageCount: 4, translationX: -100, pageWidth: 1000)
        XCTAssertEqual(visual, 1.5, accuracy: 0.001)
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

final class WallpaperClassificationTests: XCTestCase {
    private let knownAppearancePayload = "YnBsaXN0MDDSAQIDBFFsUWQQABABCA0PERMAAAAAAAABAQAAAAAAAAAFAAAAAAAAAAAAAAAAAAAAFQ=="

    func testAppearancePayloadNamesTheLightAndDarkFrames() {
        let pair = WallpaperMetadataDecoder.appearanceIndices(base64: knownAppearancePayload)
        XCTAssertEqual(pair?.light, 0)
        XCTAssertEqual(pair?.dark, 1)
        let hints = WallpaperMetadataDecoder.hints(aprBase64: knownAppearancePayload, h24Base64: nil, solarBase64: nil)
        XCTAssertEqual(WallpaperClassifier.kind(hints: hints, imageCount: 2), .lightDark)
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .lightDark, hints: hints, appearance: .light, imageCount: 2),
            .index(0)
        )
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .lightDark, hints: hints, appearance: .dark, imageCount: 2),
            .index(1)
        )
    }

    func testLightAndDarkIndicesNeedNotBeTheFirstTwoFrames() {
        let hints = WallpaperMetadataDecoder.hints(
            aprBase64: base64Plist(["l": 2, "d": 5]),
            h24Base64: nil,
            solarBase64: nil
        )
        XCTAssertEqual(hints.lightIndex, 2)
        XCTAssertEqual(hints.darkIndex, 5)
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .lightDark, hints: hints, appearance: .dark, imageCount: 8),
            .index(5)
        )
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .lightDark, hints: hints, appearance: .dark, imageCount: 4),
            .plainBlur
        )
    }

    func testABrokenAppearanceHintDoesNotGuessAFrame() {
        let hints = WallpaperMetadataDecoder.hints(aprBase64: "not-a-plist", h24Base64: nil, solarBase64: nil)
        XCTAssertTrue(hints.hasAppearanceTag)
        XCTAssertNil(hints.lightIndex)
        XCTAssertNil(hints.darkIndex)
        XCTAssertEqual(WallpaperClassifier.kind(hints: hints, imageCount: 2), .lightDark)
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .lightDark, hints: hints, appearance: .light, imageCount: 2),
            .plainBlur
        )
    }

    func testTimeOfDayWinsOverAppearanceAndIsNotAFrame() {
        let solar = base64Plist([
            "ap": ["l": 0, "d": 1],
            "si": [["i": 0, "a": 10, "z": 90]]
        ])
        let hints = WallpaperMetadataDecoder.hints(
            aprBase64: knownAppearancePayload,
            h24Base64: nil,
            solarBase64: solar
        )
        XCTAssertTrue(hints.hasTimeOfDay)
        XCTAssertEqual(WallpaperClassifier.kind(hints: hints, imageCount: 8), .timeBased)
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .timeBased, hints: hints, appearance: .dark, imageCount: 8),
            .plainBlur
        )

        let solarOnly = WallpaperMetadataDecoder.hints(aprBase64: nil, h24Base64: nil, solarBase64: solar)
        XCTAssertFalse(solarOnly.hasAppearanceTag)
        XCTAssertEqual(WallpaperClassifier.kind(hints: solarOnly, imageCount: 8), .timeBased)

        let byHour = WallpaperMetadataDecoder.hints(
            aprBase64: nil,
            h24Base64: base64Plist(["ti": [["i": 0, "t": 0.5]]]),
            solarBase64: nil
        )
        XCTAssertEqual(WallpaperClassifier.kind(hints: byHour, imageCount: 4), .timeBased)
    }

    func testAStillPictureUsesTheFirstFrame() {
        let hints = WallpaperMetadataHints.none
        XCTAssertEqual(WallpaperClassifier.kind(hints: hints, imageCount: 1), .still)
        XCTAssertEqual(
            WallpaperClassifier.frame(kind: .still, hints: hints, appearance: .dark, imageCount: 1),
            .index(0)
        )
        XCTAssertEqual(WallpaperClassifier.kind(hints: hints, imageCount: 0), .aerialOrUnknown)
    }

    func testImageProviderNamesItsFileAndIgnoresAnotherDisplay() {
        let path = "/Library/Desktop Pictures/Still.jpg"
        let store: [String: Any] = [
            "Displays": [
                "main-display": imageEntry(provider: WallpaperStoreIndex.imageProvider, path: path),
                "other-display": imageEntry(provider: WallpaperStoreIndex.imageProvider, path: "/Library/Desktop Pictures/Other.jpg")
            ],
            "AllSpacesAndDisplays": imageEntry(
                provider: WallpaperStoreIndex.imageProvider,
                path: "/Library/Desktop Pictures/Global.jpg"
            )
        ]
        let choice = WallpaperStoreIndex.choice(in: store, displayUUID: "MAIN-DISPLAY")
        XCTAssertEqual(choice?.provider, WallpaperStoreIndex.imageProvider)
        XCTAssertEqual(choice?.imageFilePath, path)
        XCTAssertEqual(choice?.configKeys, ["url"])
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: choice, workspacePath: WallpaperReportedImage.systemDefaultPath, imageFileReadable: true).source,
            .store
        )
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: choice, workspacePath: WallpaperReportedImage.systemDefaultPath, imageFileReadable: true).use,
            .imageFile(path)
        )
    }

    func testImageFolderDoesNotPickAFile() {
        let entry = imageEntry(provider: WallpaperStoreIndex.imageFolderProvider, path: "/Library/Desktop Pictures")
        let choice = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": entry], displayUUID: nil)
        XCTAssertEqual(choice?.isFolder, true)
        XCTAssertNil(choice?.imageFilePath)
        let photo = "/Library/Desktop Pictures/Current.jpg"
        let folder = WallpaperChoicePolicy.resolve(choice: choice, workspacePath: photo, imageFileReadable: false)
        XCTAssertEqual(folder.source, .store)
        XCTAssertEqual(folder.use, .plainBlur)
        XCTAssertEqual(folder.kind, .aerialOrUnknown)
    }

    func testUnknownProviderKeepsTheNameAndDoesNotGuessAFile() {
        let entry: [String: Any] = [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": "com.apple.wallpaper.choice.unknown",
                        "Configuration": binaryPlist(["assetID": "clip", "url": fileURL("/Library/Desktop Pictures/Hidden.jpg")])
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
        let choice = WallpaperStoreIndex.choice(in: ["SystemDefault": entry], displayUUID: "missing")
        XCTAssertEqual(choice?.provider, "com.apple.wallpaper.choice.unknown")
        XCTAssertNil(choice?.imageFilePath)
        XCTAssertNil(choice?.solidColor)
        let unknown = WallpaperChoicePolicy.resolve(
            choice: choice,
            workspacePath: WallpaperReportedImage.systemDefaultPath,
            imageFileReadable: false
        )
        XCTAssertEqual(unknown.source, .store)
        XCTAssertEqual(unknown.use, .plainBlur)
        let photo = "/Library/Desktop Pictures/Photo.jpg"
        let ignored = WallpaperChoicePolicy.resolve(choice: choice, workspacePath: photo, imageFileReadable: false)
        XCTAssertEqual(ignored.source, .store)
        XCTAssertEqual(ignored.use, .plainBlur)
        XCTAssertEqual(ignored.kind, .aerialOrUnknown)
    }

    func testMissingKeysReturnNilAndAMissingStoreUsesARealPhotoOnly() {
        XCTAssertNil(WallpaperStoreIndex.choice(in: [:], displayUUID: "main-display"))
        XCTAssertNil(WallpaperStoreIndex.choice(in: ["Displays": ["main-display": ["Idle": [:]]]], displayUUID: "main-display"))
        XCTAssertNil(WallpaperStoreIndex.choice(in: [
            "AllSpacesAndDisplays": ["Desktop": ["Content": ["Choices": [] as [Any]]]]
        ], displayUUID: nil))
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: nil, workspacePath: "/Library/Desktop Pictures/Photo.jpg", imageFileReadable: false).source,
            .legacy
        )
        let missing = WallpaperChoicePolicy.resolve(
            choice: nil,
            workspacePath: WallpaperReportedImage.systemDefaultPath,
            imageFileReadable: false
        )
        XCTAssertEqual(missing.source, .none)
        XCTAssertEqual(missing.use, .plainBlur)
        XCTAssertFalse(WallpaperReportedImage.isSystemDefault("/System/Example/other.heic"))
        XCTAssertTrue(WallpaperReportedImage.isSystemDefault("/System/Volumes/Data" + WallpaperReportedImage.systemDefaultPath))
    }

    func testCorruptConfigurationDoesNotCrashAndDropsItsKeys() {
        let entry: [String: Any] = [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": WallpaperStoreIndex.imageProvider,
                        "Configuration": Data("not a plist".utf8),
                        "Files": [["relative": fileURL("/Library/Desktop Pictures/Still.jpg")]]
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
        let choice = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": entry], displayUUID: nil)
        XCTAssertEqual(choice?.provider, WallpaperStoreIndex.imageProvider)
        XCTAssertEqual(choice?.configKeys, [])
        XCTAssertEqual(choice?.imageFilePath, "/Library/Desktop Pictures/Still.jpg")
        XCTAssertNil(choice?.solidColor)
    }

    func testAColourInTheConfigurationIsAFlatFill() {
        let entry = [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": WallpaperStoreIndex.colorProvider,
                        "Configuration": binaryPlist([
                            "systemColor": ["components": [1.0, 0.4, 0.1, 1.0]],
                            "type": "system"
                        ])
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
        let choice = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": entry], displayUUID: nil)
        XCTAssertEqual(choice?.configKeys, ["systemColor", "type"])
        XCTAssertTrue(choice?.colorValueLog.contains("systemColor=Dict(") == true)
        XCTAssertTrue(choice?.colorValueLog.contains("type=String(system)") == true)
        XCTAssertEqual(choice?.solidColor?.red ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(choice?.solidColor?.green ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(choice?.solidColor?.blue ?? -1, 0.1, accuracy: 0.001)
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: choice, workspacePath: WallpaperReportedImage.systemDefaultPath, imageFileReadable: false).use,
            .solid(choice?.solidColor ?? WallpaperSolidColor(red: 0, green: 0, blue: 0))
        )
    }

    func testASolidColorsImageReferenceStaysInThatDirectory() {
        let safe = "/System/Library/Desktop Pictures/Solid Colors/Red Orange.png"
        XCTAssertEqual(WallpaperStoreIndex.solidColorImagePath(from: "file://" + safe.replacingOccurrences(of: " ", with: "%20")), safe)
        XCTAssertEqual(
            WallpaperStoreIndex.solidColorImagePath(from: "Solid Colors/Red Orange.png"),
            safe
        )
        XCTAssertNil(WallpaperStoreIndex.solidColorImagePath(from: "/System/Library/Desktop Pictures/Solid Colors/../Secrets.png"))
        XCTAssertNil(WallpaperStoreIndex.solidColorImagePath(from: "/Library/Desktop Pictures/Photo.png"))
        let encoded = binaryPlist(["systemColor": "Solid Colors/Red Orange.png", "type": "system"])
        let entry: [String: Any] = [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": WallpaperStoreIndex.colorProvider,
                        "Configuration": encoded
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
        let choice = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": entry], displayUUID: nil)
        XCTAssertEqual(choice?.solidColorImagePath, safe)
        XCTAssertEqual(WallpaperLogName.configKeys(choice?.configKeys ?? []), "systemColor,type")
        XCTAssertEqual(WallpaperLogName.fileName(path: "/Library/Example/wall.jpg"), "wall.jpg")
        XCTAssertFalse(WallpaperLogName.fileName(path: "/Library/Example/wall.jpg").contains("/"))
    }

    func testBase64ConfigurationDecodesAndTheDisplayBeatsTheGlobalChoice() {
        let configuration = binaryPlist(["url": fileURL("/Library/Desktop Pictures/Desk.jpg")])
        let entry: [String: Any] = [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": WallpaperStoreIndex.imageProvider,
                        "Configuration": configuration.base64EncodedString()
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
        let store: [String: Any] = [
            "Displays": ["main-display": entry],
            "AllSpacesAndDisplays": imageEntry(
                provider: WallpaperStoreIndex.imageProvider,
                path: "/Library/Desktop Pictures/Other.jpg"
            )
        ]
        XCTAssertEqual(
            WallpaperStoreIndex.choice(in: store, displayUUID: "main-display")?.imageFilePath,
            "/Library/Desktop Pictures/Desk.jpg"
        )
    }

    func testAerialsStayUnknownWhateverTheLegacyURLSays() {
        let entry: [String: Any] = [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": WallpaperStoreIndex.aerialsProvider,
                        "Configuration": binaryPlist(["assetID": "night-city"])
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
        let choice = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": entry], displayUUID: nil)
        XCTAssertEqual(choice?.provider, WallpaperStoreIndex.aerialsProvider)
        XCTAssertEqual(choice?.configKeys, ["assetID"])
        XCTAssertNil(choice?.imageFilePath)
        let legacy = "/System/Library/Desktop Pictures/Some Time.heic"
        let decision = WallpaperChoicePolicy.resolve(choice: choice, workspacePath: legacy, imageFileReadable: true)
        XCTAssertEqual(decision.source, .store)
        XCTAssertEqual(decision.use, .plainBlur)
        XCTAssertEqual(decision.kind, .aerialOrUnknown)
        let placeholder = WallpaperChoicePolicy.resolve(
            choice: choice,
            workspacePath: WallpaperReportedImage.systemDefaultPath,
            imageFileReadable: true
        )
        XCTAssertEqual(placeholder.kind, .aerialOrUnknown)
        XCTAssertEqual(placeholder.use, .plainBlur)
    }

    func testSystemColorNameMatchesASolidColorsPNGWithoutAColourTable() {
        XCTAssertEqual(
            WallpaperSolidColorMatch.fileName(matching: "Red Orange", candidates: ["Blue.png", "RedOrange.png"]),
            "RedOrange.png"
        )
        XCTAssertEqual(
            WallpaperSolidColorMatch.fileName(matching: "red orange", candidates: ["Red Orange.png"]),
            "Red Orange.png"
        )
        XCTAssertNil(WallpaperSolidColorMatch.fileName(matching: "Red Orange", candidates: ["Blue.png"]))
        let named = WallpaperValueLog.colorProviderLine(systemColor: "Red Orange", type: 1)
        XCTAssertTrue(named.contains("systemColor=String(Red Orange)"))
        XCTAssertTrue(named.contains("type=Int(1)"))
        XCTAssertFalse(named.contains("/Users"))
        let pathLike = WallpaperValueLog.describe("/Library/Example/wall.jpg")
        XCTAssertFalse(pathLike.contains("/"))
        XCTAssertTrue(pathLike.hasPrefix("String("))
        let dark = WallpaperNeutralFill.color(for: .dark)
        let light = WallpaperNeutralFill.color(for: .light)
        XCTAssertEqual(dark.red, Double(0x30) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(dark.green, Double(0x32) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(dark.blue, Double(0x38) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(light.red, Double(0xE6) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(light.green, Double(0xE8) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(light.blue, Double(0xEB) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(WallpaperDim.black, 0.25, accuracy: 0.001)
    }

    func testAnExistingUnreadableImageIsNotReplacedByAnotherURL() {
        let stored = "/Library/Example/wall.jpg"
        let other = "/Library/Example/other.jpg"
        let choice = WallpaperStoreChoice(
            provider: WallpaperStoreIndex.imageProvider,
            configKeys: ["url"],
            imageFilePath: stored,
            isFolder: false,
            solidColor: nil,
            solidColorImagePath: nil
        )
        let blocked = WallpaperChoicePolicy.resolve(
            choice: choice,
            workspacePath: other,
            imageFileReadable: false,
            storeFileExists: true
        )
        XCTAssertEqual(blocked.source, .store)
        XCTAssertEqual(blocked.use, .plainBlur)
        XCTAssertEqual(blocked.kind, .unreadable)
        let missing = WallpaperChoicePolicy.resolve(
            choice: choice,
            workspacePath: other,
            imageFileReadable: false,
            storeFileExists: false
        )
        XCTAssertEqual(missing.source, .legacy)
        XCTAssertEqual(missing.use, .imageFile(other))
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: choice, workspacePath: other, imageFileReadable: true).use,
            .imageFile(stored)
        )
    }

    func testProtectedLocationsAreClassifiedFromThePathAndNotOpened() {
        let desktop = "/Users/example/Desktop/wall.jpg"
        let documents = "/Users/example/Documents/wall.jpg"
        let downloads = "/Users/example/Downloads/wall.jpg"
        let pictures = "/Users/example/Pictures/wall.jpg"
        let photos = "/Users/example/Pictures/Example.photoslibrary/wall.jpg"
        let icloud = "/Users/example/Library/Mobile Documents/wall.jpg"
        let volume = "/Volumes/Example/wall.jpg"
        let library = "/Library/Example/wall.jpg"
        let system = "/System/Example/wall.jpg"
        XCTAssertEqual(WallpaperPathPlace.classify(desktop), .desktop)
        XCTAssertEqual(WallpaperPathPlace.classify("~/Desktop/wall.jpg"), .desktop)
        XCTAssertEqual(WallpaperPathPlace.classify("file:///Users/example/Desktop/wall.jpg"), .desktop)
        XCTAssertEqual(WallpaperPathPlace.classify(documents), .documents)
        XCTAssertEqual(WallpaperPathPlace.classify(downloads), .downloads)
        XCTAssertEqual(WallpaperPathPlace.classify(pictures), .pictures)
        XCTAssertEqual(WallpaperPathPlace.classify(photos), .photosLibrary)
        XCTAssertEqual(WallpaperPathPlace.classify(icloud), .icloud)
        XCTAssertEqual(WallpaperPathPlace.classify("~/Library/Mobile Documents/wall.jpg"), .icloud)
        XCTAssertEqual(WallpaperPathPlace.classify(volume), .volumes)
        XCTAssertEqual(WallpaperPathPlace.classify(library), .system)
        XCTAssertEqual(WallpaperPathPlace.classify(system), .system)
        for path in [desktop, documents, downloads, photos, icloud, volume] {
            XCTAssertTrue(WallpaperPathPlace.classify(path).isProtected)
            let plan = WallpaperFileGate.plan(paths: [path])
            XCTAssertTrue(plan.statPaths.isEmpty)
            XCTAssertNotNil(plan.blockedPlace)
        }
        XCTAssertFalse(WallpaperPathPlace.classify(pictures).isProtected)
        XCTAssertFalse(WallpaperPathPlace.classify(library).isProtected)
        XCTAssertFalse(WallpaperPathPlace.classify(system).isProtected)
        XCTAssertEqual(WallpaperFileGate.plan(paths: [pictures]).statPaths, [pictures])
        XCTAssertEqual(WallpaperFileGate.plan(paths: [library]).statPaths, [library])
        XCTAssertEqual(WallpaperFileGate.plan(paths: [system]).statPaths, [system])
        let mixed = WallpaperFileGate.plan(paths: [desktop, library])
        XCTAssertEqual(mixed.statPaths, [library])
        XCTAssertEqual(mixed.blockedPlace, .desktop)
        XCTAssertFalse(mixed.statPaths.contains(desktop))
        let dotDot = "/Library/Example/../../Users/example/Desktop/wall.jpg"
        XCTAssertEqual(WallpaperPathPlace.classify(dotDot), .desktop)
        XCTAssertTrue(WallpaperFileGate.plan(paths: [dotDot]).statPaths.isEmpty)

        let stored = WallpaperStoreChoice(
            provider: WallpaperStoreIndex.imageProvider,
            configKeys: ["url"],
            imageFilePath: desktop,
            isFolder: false,
            solidColor: nil,
            solidColorImagePath: nil
        )
        let refused = WallpaperChoicePolicy.resolve(
            choice: stored,
            workspacePath: library,
            imageFileReadable: true
        )
        XCTAssertEqual(refused.use, .plainBlur)
        XCTAssertEqual(refused.kind, .fallback)
        let legacyOnly = WallpaperChoicePolicy.resolve(
            choice: nil,
            workspacePath: desktop,
            imageFileReadable: true
        )
        XCTAssertEqual(legacyOnly.use, .plainBlur)
        XCTAssertNotEqual(legacyOnly.use, .imageFile(desktop))
        let line = WallpaperURLLog.protected(
            shape: "String",
            filesCount: 0,
            pathParsed: true,
            place: WallpaperPathPlace.desktop.rawValue,
            ext: "jpg"
        )
        XCTAssertEqual(line, "urlShape=String filesCount=0 pathParsed=true place=desktop skipped=protected ext=jpg")
        XCTAssertFalse(line.contains("exists="))
        XCTAssertFalse(line.contains("readable="))
        XCTAssertFalse(line.contains("example"))
    }

    func testPictureURLShapesAndColourNames() {
        let plain = WallpaperURLParser.parse(url: "file:///Library/Example/wall.jpg", files: nil)
        XCTAssertEqual(plain.shape, "String")
        XCTAssertEqual(plain.paths, ["/Library/Example/wall.jpg"])
        let relative = WallpaperURLParser.parse(
            url: ["relative": "/Library/Example/wall.jpg"],
            files: nil
        )
        XCTAssertEqual(relative.shape, "Dict(relative)")
        XCTAssertEqual(relative.paths, ["/Library/Example/wall.jpg"])
        let joined = WallpaperURLParser.parse(
            url: ["base": "file:///Library/Example/", "relative": "wall.jpg"],
            files: nil
        )
        XCTAssertEqual(joined.shape, "Dict(base,relative)")
        XCTAssertEqual(joined.paths, ["/Library/Example/wall.jpg"])
        let blob = Data([1, 2, 3, 4])
        let bookmark = WallpaperURLParser.parse(url: blob, files: nil)
        XCTAssertEqual(bookmark.shape, "Data")
        XCTAssertEqual(bookmark.bookmarks, [blob])
        XCTAssertTrue(bookmark.paths.isEmpty)
        XCTAssertTrue(WallpaperFileGate.plan(paths: bookmark.paths).statPaths.isEmpty)
        let files: [Any] = [
            ["relative": "/Library/Example/first.jpg"],
            ["relative": "/Library/Example/wall.jpg"]
        ]
        let many = WallpaperURLParser.parse(url: nil, files: files)
        XCTAssertEqual(many.filesCount, 2)
        XCTAssertEqual(many.shape, "none")
        XCTAssertEqual(many.paths, ["/Library/Example/first.jpg", "/Library/Example/wall.jpg"])
        XCTAssertEqual(WallpaperSystemColor.enumName(from: ["cyan": [String: Any]()]), "cyan")
        XCTAssertEqual(WallpaperSystemColor.enumName(from: ["dustyRose": [String: Any]()]), "dustyRose")
        XCTAssertNil(WallpaperSystemColor.enumName(from: ["cyan": ["extra": 1]]))
        XCTAssertNil(WallpaperSystemColor.enumName(from: ["cyan": [String: Any](), "other": [String: Any]()]))
        XCTAssertEqual(WallpaperSolidColorMatch.normalize("dustyRose"), "dustyrose")
        XCTAssertEqual(WallpaperSolidColorMatch.normalize("Dusty Rose.png"), "dustyrose")
        XCTAssertEqual(
            WallpaperSolidColorMatch.fileName(matching: "dustyRose", candidates: ["Cyan.png", "Dusty Rose.png"]),
            "Dusty Rose.png"
        )
        XCTAssertNil(WallpaperSolidColorMatch.fileName(matching: "cyan", candidates: ["Cyanide.png"]))
        let archive = Data("bplist00$archiver".utf8)
        XCTAssertTrue(WallpaperKeyedArchive.isKeyedArchive(archive))
        XCTAssertFalse(WallpaperKeyedArchive.isKeyedArchive(Data("plain".utf8)))
        let probe = WallpaperStructureProbe.inspect(
            desktop: ["note": "/Library/Example/wall.jpg", "swatch": ["components": [0.1, 0.2, 0.3]]],
            content: ["title": "plain"],
            choice: ["blob": archive]
        )
        XCTAssertFalse(probe.line.contains("/"))
        XCTAssertTrue(probe.line.contains("components=[0.1000,0.2000,0.3000]"))
        XCTAssertEqual(probe.archive, archive)
        let checked = WallpaperURLLog.line(
            shape: "String",
            filesCount: 0,
            pathParsed: true,
            exists: "true",
            readable: "false",
            place: "system",
            ext: "jpg",
            reason: "unreadable"
        )
        XCTAssertEqual(
            checked,
            "urlShape=String filesCount=0 pathParsed=true exists=true readable=false place=system ext=jpg reason=unreadable"
        )
        XCTAssertFalse(checked.contains("/Library"))
    }

    func testCustomColourIsReadInEveryStoredEncoding() {
        let components: [String: Any] = ["components": [0.2, 0.4, 0.6, 1.0]]
        for payload in storedEncodings(customColor: components) {
            let choice = customChoice(payload.configuration, encodedOptions: payload.options, linked: payload.linked)
            XCTAssertEqual(choice?.solidColor?.red ?? -1, 0.2, accuracy: 0.001)
            XCTAssertEqual(choice?.solidColor?.green ?? -1, 0.4, accuracy: 0.001)
            XCTAssertEqual(choice?.solidColor?.blue ?? -1, 0.6, accuracy: 0.001)
            XCTAssertEqual(
                WallpaperChoicePolicy.resolve(choice: choice, workspacePath: nil, imageFileReadable: false).use,
                .solid(choice?.solidColor ?? WallpaperSolidColor(red: 0, green: 0, blue: 0))
            )
        }

        let channels = customChoice(configuration(["customColor": ["red": 0.2, "green": 0.4, "blue": 0.6]]))
        XCTAssertEqual(channels?.solidColor?.red ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(channels?.solidColor?.green ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(channels?.solidColor?.blue ?? -1, 0.6, accuracy: 0.001)
        let short = customChoice(configuration(["customColor": ["r": 51, "g": 102, "b": 153]]))
        XCTAssertEqual(short?.solidColor?.red ?? -1, 51.0 / 255, accuracy: 0.001)
        XCTAssertEqual(short?.solidColor?.green ?? -1, 102.0 / 255, accuracy: 0.001)
        XCTAssertEqual(short?.solidColor?.blue ?? -1, 153.0 / 255, accuracy: 0.001)
        let grey = customChoice(configuration(["customColor": [0.25]]))
        XCTAssertEqual(grey?.solidColor?.red ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(grey?.solidColor?.green ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(grey?.solidColor?.blue ?? -1, 0.25, accuracy: 0.001)

        let nested = linkedCustomChoice(customColor: [
            "color": ["_0": ["color": ["colorSpace": 16, "components": [0.2, 0.4, 0.6, 1.0]]]]
        ])
        XCTAssertEqual(nested?.solidColor?.red ?? -1, 0.2, accuracy: 0.001)
        XCTAssertEqual(nested?.solidColor?.green ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(nested?.solidColor?.blue ?? -1, 0.6, accuracy: 0.001)
        XCTAssertFalse(nested?.colorValueLog.contains("/") == true)
    }

    func testOtherWallpaperTypesIgnoreCustomColour() {
        let peach = ["components": [1.0, 0.8, 0.64, 1.0]]
        let system = customChoice([
            "type": "system",
            "systemColor": ["components": [0.0, 0.0, 1.0, 1.0]],
            "values": ["customColor": peach]
        ])
        XCTAssertEqual(system?.solidColor?.blue ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(system?.solidColor?.red ?? -1, 0, accuracy: 0.001)
        let named = customChoice(
            ["type": "systemColor", "systemColor": ["plum": [String: Any]()], "values": ["customColor": peach]],
            encodedOptions: ["values": ["customColor": peach]]
        )
        XCTAssertNil(named?.solidColor)
        XCTAssertEqual(named?.systemColorName, "plum")
        let shuffle = customChoice(["type": "shuffle", "values": ["customColor": peach]])
        XCTAssertNil(shuffle?.solidColor)
        let numbered = customChoice(["type": 1, "values": ["customColor": peach]])
        XCTAssertNil(numbered?.solidColor)

        let picture = imageEntry(provider: WallpaperStoreIndex.imageProvider, path: "/Library/Desktop Pictures/Still.jpg")
        var content = ((picture["Desktop"] as? [String: Any])?["Content"] as? [String: Any]) ?? [:]
        content["EncodedOptionValues"] = binaryPlist(["values": ["customColor": peach]])
        var desktop = picture["Desktop"] as? [String: Any] ?? [:]
        desktop["Content"] = content
        var stored = picture
        stored["Desktop"] = desktop
        let image = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": stored], displayUUID: nil)
        XCTAssertEqual(image?.imageFilePath, "/Library/Desktop Pictures/Still.jpg")
        XCTAssertNil(image?.solidColor)
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: image, workspacePath: nil, imageFileReadable: true).use,
            .imageFile("/Library/Desktop Pictures/Still.jpg")
        )
        var withLinkedColour = stored
        withLinkedColour["Linked"] = [
            "Content": [
                "Choices": [[
                    "Provider": WallpaperStoreIndex.colorProvider,
                    "Configuration": ["type": "customColor", "values": ["customColor": peach]]
                ] as [String: Any]] as [Any]
            ]
        ]
        let kept = WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": withLinkedColour], displayUUID: nil)
        XCTAssertEqual(kept?.imageFilePath, "/Library/Desktop Pictures/Still.jpg")
        XCTAssertNil(kept?.solidColor)

        let linkedPicture: [String: Any] = [
            "Linked": [
                "Content": [
                    "Choices": [[
                        "Provider": WallpaperStoreIndex.imageProvider,
                        "Configuration": binaryPlist([
                            "type": "imageFile",
                            "url": fileURL("/Library/Desktop Pictures/Still.jpg")
                        ])
                    ] as [String: Any]] as [Any],
                    "EncodedOptionValues": binaryPlist(["values": ["customColor": peach]])
                ]
            ]
        ]
        XCTAssertNil(WallpaperStoreIndex.choice(in: ["Displays": ["main-display": linkedPicture]], displayUUID: "main-display"))
    }

    func testMissingOrGarbageCustomColourFallsBack() {
        let missing = customChoice(["type": "customColor"])
        XCTAssertNil(missing?.solidColor)
        XCTAssertEqual(fallbackUse(missing), .plainBlur)
        let absent = customChoice(["type": "customColor", "values": ["note": "none"]])
        XCTAssertNil(absent?.solidColor)
        XCTAssertEqual(fallbackUse(absent), .plainBlur)
        let text = customChoice(configuration(["customColor": "not-a-colour"]))
        XCTAssertNil(text?.solidColor)
        XCTAssertEqual(fallbackUse(text), .plainBlur)
        let broken = customChoice(configuration(["customColor": ["components": ["nope"]]]))
        XCTAssertNil(broken?.solidColor)
        XCTAssertEqual(fallbackUse(broken), .plainBlur)
        let range = customChoice(configuration(["customColor": ["components": [300.0, 0.0, 0.0]]]))
        XCTAssertNil(range?.solidColor)
        XCTAssertEqual(fallbackUse(range), .plainBlur)
        let blob = linkedCustomChoice(encodedValues: Data("not a plist".utf8))
        XCTAssertNil(blob?.solidColor)
        XCTAssertEqual(fallbackUse(blob), .plainBlur)
        XCTAssertFalse(text?.colorValueLog.contains("/") == true)
    }

    func testCustomColourInkFollowsTheFillAndIgnoresThePreviousInk() {
        let peachFill = customFill(red: 0xFF, green: 0xCB, blue: 0xA4)
        XCTAssertEqual(Ink.forBackdrop(.solidColor(peachFill), previous: .light), .dark)
        XCTAssertEqual(Ink.forBackdrop(.solidColor(peachFill), previous: .dark), .dark)
        XCTAssertEqual(InkContrast.forFill(peachFill).ink, .dark)
        XCTAssertEqual(InkContrast.forFill(peachFill).veil, WallpaperDim.black)

        let darkFill = customFill(red: 0x1A, green: 0x1A, blue: 0x1C)
        XCTAssertEqual(Ink.forBackdrop(.solidColor(darkFill), previous: .light), .light)
        XCTAssertEqual(Ink.forBackdrop(.solidColor(darkFill), previous: .dark), .light)
        XCTAssertEqual(InkContrast.forFill(darkFill).ink, .light)
        XCTAssertEqual(
            Ink.forBackdrop(.solidColor(darkFill), previous: .light),
            Ink.forBackdrop(.solidColor(darkFill), previous: .dark)
        )
    }

    func testAerialChoiceKeepsTheAssetIDFromDesktopAndFromLinked() {
        let desktop = aerialChoice(record: "Desktop", configuration: ["assetID": "CITY-1"])
        XCTAssertEqual(desktop?.provider, WallpaperStoreIndex.aerialsProvider)
        XCTAssertEqual(desktop?.aerialAssetID, "CITY-1")
        XCTAssertEqual(desktop?.aerialRecord, "Desktop")
        XCTAssertNil(desktop?.imageFilePath)
        XCTAssertEqual(
            WallpaperChoicePolicy.resolve(choice: desktop, workspacePath: "/Library/Desktop Pictures/Other.heic", imageFileReadable: true).use,
            .plainBlur
        )

        let linked = aerialChoice(record: "Linked", configuration: binaryPlist(["assetID": "LINKED-1"]))
        XCTAssertEqual(linked?.provider, WallpaperStoreIndex.aerialsProvider)
        XCTAssertEqual(linked?.aerialAssetID, "LINKED-1")
        XCTAssertEqual(linked?.aerialRecord, "Linked")

        let linkedPicture = aerialChoice(
            record: "Linked",
            configuration: binaryPlist(["url": fileURL("/Library/Desktop Pictures/Still.jpg")]),
            provider: WallpaperStoreIndex.imageProvider
        )
        XCTAssertNil(linkedPicture)

        var both = aerialEntry(record: "Desktop", configuration: ["assetID": "DESK"])
        both["Linked"] = aerialEntry(record: "Linked", configuration: ["assetID": "LINK"])["Linked"]
        both["Idle"] = aerialEntry(record: "Desktop", configuration: ["assetID": "IDLE"])["Desktop"]
        let winner = WallpaperStoreIndex.choice(in: ["Displays": ["main-display": both]], displayUUID: "main-display")
        XCTAssertEqual(winner?.aerialAssetID, "DESK")
        XCTAssertEqual(winner?.aerialRecord, "Desktop")

        let idleOnly = ["Idle": aerialEntry(record: "Desktop", configuration: ["assetID": "IDLE"])["Desktop"] as Any]
        XCTAssertNil(WallpaperStoreIndex.choice(in: ["Displays": ["main-display": idleOnly]], displayUUID: "main-display"))
        XCTAssertNil(WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": ["Idle": ["Content": [:]]]], displayUUID: nil))
    }

    func testAerialAssetIDIsReadFromConfigurationAndFromEncodedOptions() {
        let direct = aerialChoice(record: "Desktop", configuration: binaryPlist(["assetID": "FROM-CONFIG"]))
        XCTAssertEqual(direct?.aerialAssetID, "FROM-CONFIG")
        XCTAssertNil(direct?.aerialSubcategory)

        let nested = aerialChoice(record: "Desktop", configuration: ["values": ["assetID": "NESTED-1"]])
        XCTAssertEqual(nested?.aerialAssetID, "NESTED-1")

        let fromOptions = aerialChoice(
            record: "Desktop",
            configuration: binaryPlist(["type": "aerial"]),
            encodedOptions: binaryPlist(["values": ["assetID": "FROM-OPTIONS"]])
        )
        XCTAssertEqual(fromOptions?.aerialAssetID, "FROM-OPTIONS")

        let configWins = aerialChoice(
            record: "Linked",
            configuration: ["assetID": "CONFIG-WINS"],
            encodedOptions: ["assetID": "OPTIONS-LOSE"]
        )
        XCTAssertEqual(configWins?.aerialAssetID, "CONFIG-WINS")
        XCTAssertEqual(configWins?.aerialRecord, "Linked")
    }

    func testAerialSubcategoryCatalogueLogsAndMissingMovie() {
        let remote = "https://example.com/sea.mov"
        let catalogue: [String: Any] = [
            "assets": [
                ["id": "SEA-1", "url-4K-SDR-240FPS": remote, "previewImage": "https://example.com/sea.jpg"],
                ["id": "CITY-2", "url-4K-HDR": "https://example.com/city.mov"]
            ],
            "categories": [
                [
                    "id": "places",
                    "previewImage": "https://example.com/places.jpg",
                    "subcategories": [
                        ["id": "ocean", "representativeAssetID": "SEA-1", "previewImage": remote]
                    ]
                ]
            ]
        ]
        let stored = aerialChoice(record: "Desktop", configuration: ["subcategory": "ocean"])
        XCTAssertNil(stored?.aerialAssetID)
        XCTAssertEqual(stored?.aerialSubcategory, "ocean")
        XCTAssertEqual(
            WallpaperAerialCatalogue.resolvedAssetID(
                storedAssetID: stored?.aerialAssetID,
                subcategory: stored?.aerialSubcategory,
                catalogue: catalogue
            ),
            "SEA-1"
        )
        let catalogueData = try? JSONSerialization.data(withJSONObject: catalogue)
        XCTAssertEqual(
            WallpaperAerialCatalogue.representativeAssetID(forSubcategory: "ocean", in: catalogueData),
            "SEA-1"
        )
        XCTAssertNil(WallpaperAerialCatalogue.resolvedAssetID(storedAssetID: nil, subcategory: "no-such", catalogue: catalogue))
        XCTAssertNil(WallpaperAerialCatalogue.resolvedAssetID(storedAssetID: nil, subcategory: "ocean", catalogue: ["assets": []]))
        XCTAssertNil(WallpaperAerialCatalogue.resolvedAssetID(storedAssetID: "/Users/example/secret", subcategory: "ocean", catalogue: catalogue))

        let videos = URL(fileURLWithPath: "/Library/GridBack Aerial Fixture", isDirectory: true)
        let urls = WallpaperAerialCatalogue.localVideoURLs(in: catalogue, videosDirectory: videos)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["SEA-1.mov", "CITY-2.mov"])
        XCTAssertTrue(urls.allSatisfy { $0.isFileURL && $0.scheme == "file" })
        let joined = urls.map(\.absoluteString).joined(separator: " ")
        XCTAssertFalse(joined.contains("https"))
        XCTAssertFalse(joined.contains("http"))
        XCTAssertFalse(joined.contains("example.com"))
        XCTAssertFalse(joined.contains("/Users/"))
        let sea = WallpaperAerialCatalogue.localVideoURL(assetID: "SEA-1", videosDirectory: videos)
        XCTAssertEqual(sea?.isFileURL, true)
        XCTAssertFalse(sea?.absoluteString.contains(remote) == true)
        XCTAssertNil(WallpaperAerialCatalogue.localVideoURL(assetID: "../SEA-1", videosDirectory: videos))
        XCTAssertNil(WallpaperAerialCatalogue.localVideoURL(assetID: "SEA-1", videosDirectory: URL(string: "https://example.com/videos")!))
        XCTAssertTrue(WallpaperAerialCatalogue.localVideoURLs(in: catalogue, videosDirectory: URL(string: "https://example.com/videos")!).isEmpty)

        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gridback-aerial-missing", isDirectory: true)
        try? FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: missing.appendingPathComponent("SEA-1.mov"))
        XCTAssertEqual(WallpaperAerialCatalogue.kind(assetID: "SEA-1", videosDirectory: missing), .fallback)
        XCTAssertEqual(WallpaperAerialCatalogue.kind(assetID: nil, videosDirectory: missing), .fallback)
        XCTAssertNil(WallpaperAerialCatalogue.localMovie(assetID: "SEA-1", videosDirectory: missing))
        XCTAssertEqual(WallpaperAerialCatalogue.frameFraction, 0.25, accuracy: 0.000_1)

        let record = WallpaperAerialLog.recordLine(
            record: "Desktop",
            provider: WallpaperStoreIndex.aerialsProvider,
            keys: ["assetID", "subcategory"]
        )
        let matched = WallpaperAerialLog.matchLine(matched: true, assetID: "SEA-1")
        let hidden = WallpaperAerialLog.matchLine(matched: false, assetID: "/Users/example/secret.mov")
        let redacted = WallpaperAerialLog.recordLine(record: "Linked", provider: "/Users/example/evil", keys: ["/Users/example"])
        let lines = [record, matched, hidden, redacted].joined(separator: "\n")
        XCTAssertFalse(lines.contains("/Users/"))
        XCTAssertFalse(lines.contains("example"))
        XCTAssertTrue(record.contains("record=Desktop"))
        XCTAssertTrue(record.contains("provider=\(WallpaperStoreIndex.aerialsProvider)"))
        XCTAssertEqual(matched, "matched=true assetID=SEA-1")
        XCTAssertEqual(hidden, "matched=false")
        XCTAssertEqual(
            Ink.forBackdrop(.picture, previous: .dark),
            .light
        )
        XCTAssertEqual(
            BackdropInkSource.resolve(hasPicture: true, isSolidColor: false, fill: WallpaperNeutralFill.color(for: .light)),
            .picture
        )
    }

    private func aerialChoice(record: String, configuration: Any, encodedOptions: Any? = nil, provider: String = WallpaperStoreIndex.aerialsProvider) -> WallpaperStoreChoice? {
        let entry = aerialEntry(record: record, configuration: configuration, encodedOptions: encodedOptions, provider: provider)
        return WallpaperStoreIndex.choice(in: ["Displays": ["MAIN-display": entry]], displayUUID: "main-display")
    }

    private func aerialEntry(record: String, configuration: Any, encodedOptions: Any? = nil, provider: String = WallpaperStoreIndex.aerialsProvider) -> [String: Any] {
        var content: [String: Any] = [
            "Choices": [[
                "Provider": provider,
                "Configuration": configuration
            ] as [String: Any]] as [Any]
        ]
        if let encodedOptions {
            content["EncodedOptionValues"] = encodedOptions
        }
        return [record: ["Content": content]]
    }

    private func customFill(red: Int, green: Int, blue: Int) -> WallpaperSolidColor {
        let color: [String: Any] = [
            "color": [
                "_0": [
                    "color": [
                        "colorSpace": 16,
                        "components": [Double(red) / 255, Double(green) / 255, Double(blue) / 255, 1.0]
                    ]
                ]
            ]
        ]
        let choice = linkedCustomChoice(customColor: color)
        let fill = choice?.solidColor ?? WallpaperSolidColor(red: -1, green: -1, blue: -1)
        XCTAssertEqual(fill.red, Double(red) / 255, accuracy: 0.000_1)
        XCTAssertEqual(fill.green, Double(green) / 255, accuracy: 0.000_1)
        XCTAssertEqual(fill.blue, Double(blue) / 255, accuracy: 0.000_1)
        let use = WallpaperChoicePolicy.resolve(choice: choice, workspacePath: nil, imageFileReadable: false)
        XCTAssertEqual(use.kind, .solidColor)
        if case .solid(let solid) = use.use {
            XCTAssertEqual(solid.red, fill.red, accuracy: 0.000_1)
            XCTAssertEqual(solid.green, fill.green, accuracy: 0.000_1)
            XCTAssertEqual(solid.blue, fill.blue, accuracy: 0.000_1)
        } else {
            XCTFail("custom colour was not a flat fill")
        }
        return fill
    }

    private func fallbackUse(_ choice: WallpaperStoreChoice?) -> WallpaperUse {
        WallpaperChoicePolicy.resolve(choice: choice, workspacePath: nil, imageFileReadable: false).use
    }

    private func configuration(_ customColor: Any) -> [String: Any] {
        ["type": "customColor", "values": customColor]
    }

    private func storedEncodings(customColor: Any) -> [(configuration: Any, options: Any?, linked: Bool)] {
        let payload = configuration(["customColor": customColor])
        let values = binaryPlist(["values": ["customColor": customColor]])
        let typeOnly = binaryPlist(["type": "customColor"])
        return [
            (payload, nil, false),
            (binaryPlist(payload), nil, false),
            (binaryPlist(payload).base64EncodedString(), nil, false),
            (xmlPlist(payload), nil, false),
            (typeOnly, values, true),
            (typeOnly, values.base64EncodedString(), true),
            (typeOnly, xmlPlistData(["values": ["customColor": customColor]]), true)
        ]
    }

    private func customChoice(_ configuration: Any, encodedOptions: Any? = nil, linked: Bool = false) -> WallpaperStoreChoice? {
        let entry = colorContent(configuration: configuration, encodedOptions: encodedOptions, linked: linked)
        return WallpaperStoreIndex.choice(in: ["AllSpacesAndDisplays": entry], displayUUID: nil)
    }

    private func linkedCustomChoice(customColor: Any) -> WallpaperStoreChoice? {
        linkedCustomChoice(
            configuration: binaryPlist(["type": "customColor"]),
            encodedValues: binaryPlist(["values": ["customColor": customColor]])
        )
    }

    private func linkedCustomChoice(encodedValues: Any) -> WallpaperStoreChoice? {
        linkedCustomChoice(configuration: binaryPlist(["type": "customColor"]), encodedValues: encodedValues)
    }

    private func linkedCustomChoice(configuration: Any, encodedValues: Any) -> WallpaperStoreChoice? {
        let entry = colorContent(configuration: configuration, encodedOptions: encodedValues, linked: true)
        return WallpaperStoreIndex.choice(in: ["Displays": ["MAIN-display": entry]], displayUUID: "main-display")
    }

    private func colorContent(configuration: Any, encodedOptions: Any?, linked: Bool) -> [String: Any] {
        var content: [String: Any] = [
            "Choices": [[
                "Provider": WallpaperStoreIndex.colorProvider,
                "Configuration": configuration
            ] as [String: Any]] as [Any]
        ]
        if let encodedOptions {
            content["EncodedOptionValues"] = encodedOptions
        }
        let key = linked ? "Linked" : "Desktop"
        return [key: ["Content": content]]
    }

    private func xmlPlist(_ object: [String: Any]) -> String {
        String(data: xmlPlistData(object), encoding: .utf8) ?? ""
    }

    private func xmlPlistData(_ object: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    private func fileURL(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    private func imageEntry(provider: String, path: String) -> [String: Any] {
        [
            "Desktop": [
                "Content": [
                    "Choices": [[
                        "Provider": provider,
                        "Configuration": binaryPlist(["url": fileURL(path)])
                    ] as [String: Any]] as [Any]
                ]
            ]
        ]
    }

    private func base64Plist(_ object: [String: Any]) -> String {
        binaryPlist(object).base64EncodedString()
    }

    private func binaryPlist(_ object: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }
}
