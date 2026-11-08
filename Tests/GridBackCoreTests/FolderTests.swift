import XCTest
import GridBackCore

final class FolderTests: XCTestCase {
    private let twoByTwo = GridMetrics(columns: 2, rows: 2)

    func testVersionOneLayoutStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gridback-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PersistenceStore(directoryURL: directory)
        let body = """
        {
          "layout" : {
            "metrics" : { "columns" : 2, "rows" : 2 },
            "pages" : [ ["a", "b"], ["c"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 1
        }
        """
        try Data(body.utf8).write(to: store.stateURL)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.layout.orderedIDs, ["a", "b", "c"])
        XCTAssertTrue(loaded.layout.folders.isEmpty)
    }

    func testGroupingCreatesAFolderAndDoesNotDuplicateTheApps() {
        let layout = Layout(pages: [["a", "b", "c"]], metrics: twoByTwo)
        let grouped = FolderEditing.group(layout: layout, draggedAppID: "c", targetID: "a")
        XCTAssertEqual(grouped.folders.count, 1)
        XCTAssertEqual(grouped.folders[0].appIDs, ["a", "c"])
        XCTAssertEqual(grouped.orderedIDs.filter { $0 == "a" }.count, 1)
        XCTAssertEqual(grouped.orderedIDs.filter { $0 == "c" }.count, 1)
        XCTAssertEqual(grouped.orderedIDs, ["a", "c", "b"])
        XCTAssertEqual(grouped.pages[0].count, 2)
    }

    func testAddingToAnExistingFolderAndRemovingTheLastAppDeletesTheFolder() {
        let created = FolderEditing.group(
            layout: Layout(pages: [["a", "b", "c"]], metrics: twoByTwo),
            draggedAppID: "b",
            targetID: "a"
        )
        let folderID = created.pages[0][0].id
        let added = FolderEditing.group(layout: created, draggedAppID: "c", targetID: folderID)
        XCTAssertEqual(added.folders.count, 1)
        XCTAssertEqual(added.folders[0].appIDs, ["a", "b", "c"])
        XCTAssertEqual(Set(added.orderedIDs), ["a", "b", "c"])

        var taken = added
        for id in ["a", "b", "c"] {
            taken = FolderEditing.moveAppOut(layout: taken, appID: id, toPage: 0, toSlot: taken.pages.first?.count ?? 0)
        }
        XCTAssertTrue(taken.folders.isEmpty)
        XCTAssertEqual(Set(taken.orderedIDs), ["a", "b", "c"])
        XCTAssertEqual(taken.orderedIDs.count, 3)
    }

    func testEnteringANeighborDoesNotMoveItUntilTheHoldFinishes() {
        let layout = Layout(pages: [["font", "image", "meter"]], metrics: GridMetrics(columns: 7, rows: 5))
        var session = GridReorderSession(appID: "font", layout: layout, page: 0)
        let items = session.preview.pages[0]
        let entered = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: items,
            slot: 1,
            overIconCenter: true,
            dwellSeconds: 0
        )
        XCTAssertEqual(entered, .hold(targetID: "image", armed: false))
        apply(entered, to: &session)
        XCTAssertEqual(session.preview.orderedIDs, ["font", "image", "meter"])

        let still = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: session.preview.pages[0],
            slot: 1,
            overIconCenter: true,
            dwellSeconds: 0.49
        )
        XCTAssertEqual(still, .hold(targetID: "image", armed: false))
        apply(still, to: &session)
        XCTAssertEqual(session.preview.orderedIDs, ["font", "image", "meter"])

        let armed = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: session.preview.pages[0],
            slot: 1,
            overIconCenter: true,
            dwellSeconds: 0.5
        )
        XCTAssertEqual(armed, .hold(targetID: "image", armed: true))
        apply(armed, to: &session)
        XCTAssertEqual(session.preview.orderedIDs, ["font", "image", "meter"])
    }

    func testLeavingTheIconBeforeTheHoldReordersInTheGap() {
        let layout = Layout(pages: [["font", "image", "meter"]], metrics: GridMetrics(columns: 7, rows: 5))
        var session = GridReorderSession(appID: "font", layout: layout, page: 0)
        let cancelled = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: session.preview.pages[0],
            slot: 1,
            overIconCenter: true,
            dwellSeconds: 0.2
        )
        XCTAssertEqual(cancelled, .hold(targetID: "image", armed: false))
        apply(cancelled, to: &session)
        XCTAssertEqual(session.preview.orderedIDs, ["font", "image", "meter"])

        let gap = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: session.preview.pages[0],
            slot: nil,
            overIconCenter: false,
            dwellSeconds: 0
        )
        XCTAssertEqual(gap, .reorder(slot: nil))
        apply(.reorder(slot: 3), to: &session)
        XCTAssertEqual(session.preview.orderedIDs, ["image", "meter", "font"])
    }

    func testDraggingAFolderStillReordersAndDoesNotNest() {
        let layout = Layout(pages: [["font", "image"]], metrics: GridMetrics(columns: 7, rows: 5))
        let resolution = DragArbitration.resolve(
            draggedID: "folder.1",
            draggedIsFolder: true,
            items: [.folder("folder.1"), .app("image")],
            slot: 1,
            overIconCenter: true,
            dwellSeconds: 2
        )
        XCTAssertEqual(resolution, .reorder(slot: 1))
        XCTAssertEqual(
            FolderDrop.decision(draggedIsFolder: true, hoveredID: "image", pointerOverIconCenter: true, dwellSeconds: 2),
            .reorder
        )
        _ = layout
    }

    func testIconCenterOnARealGridStaysTheNeighborWhileTheGapDoesNot() {
        let grid = LaunchGridLayout.make(overlayWidth: 1728, overlayHeight: 1117, columns: 7, rows: 5)
        let imageSlot = 4
        let centerX = grid.originX + grid.columnCenter(imageSlot)
        let centerY = grid.originY + grid.rowCenter(imageSlot) - (grid.labelHeight + grid.iconLabelGap) / 2
        XCTAssertEqual(grid.hitSlot(x: centerX, y: centerY), imageSlot)
        XCTAssertTrue(grid.isOverIconCenter(x: centerX, y: centerY, slot: imageSlot))
        let items: [GridItem] = ["a", "b", "c", "font", "image", "meter"]
        let onIcon = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: items,
            slot: grid.hitSlot(x: centerX, y: centerY),
            overIconCenter: true,
            dwellSeconds: 0
        )
        XCTAssertEqual(onIcon, .hold(targetID: "image", armed: false))

        let gapX = grid.originX + grid.columnStride * 4
        XCTAssertNil(grid.hitSlot(x: gapX, y: centerY))
        let gap = DragArbitration.resolve(
            draggedID: "font",
            draggedIsFolder: false,
            items: items,
            slot: nil,
            overIconCenter: false,
            dwellSeconds: 0
        )
        XCTAssertEqual(gap, .reorder(slot: nil))
        XCTAssertNotNil(grid.insertionSlot(x: gapX, y: centerY, itemCount: items.count))
    }

    func testDraggingAFolderDoesNotNest() {
        XCTAssertEqual(
            FolderDrop.decision(draggedIsFolder: true, hoveredID: "a", pointerOverIconCenter: true, dwellSeconds: 2),
            .reorder
        )
        XCTAssertEqual(
            FolderDrop.decision(draggedIsFolder: false, hoveredID: "a", pointerOverIconCenter: true, dwellSeconds: 0.1),
            .reorder
        )
        XCTAssertEqual(
            FolderDrop.decision(draggedIsFolder: false, hoveredID: "a", pointerOverIconCenter: false, dwellSeconds: 2),
            .reorder
        )
        XCTAssertEqual(
            FolderDrop.decision(draggedIsFolder: false, hoveredID: "a", pointerOverIconCenter: true, dwellSeconds: 0.5),
            .combine(targetID: "a")
        )
    }

    private func apply(_ resolution: DragResolution, to session: inout GridReorderSession) {
        if case .reorder(let slot) = resolution {
            session.hover(slot: slot, edge: nil)
        }
    }

    func testRenameAndSearchOrderIncludeFolderApps() {
        let grouped = FolderEditing.group(
            layout: Layout(pages: [["notes", "mail"]], metrics: .classic),
            draggedAppID: "mail",
            targetID: "notes"
        )
        let renamed = FolderEditing.rename(layout: grouped, folderID: grouped.folders[0].id, name: "  Work  ")
        XCTAssertEqual(renamed.folders[0].name, "Work")
        XCTAssertEqual(renamed.orderedIDs, ["notes", "mail"])
        let apps = renamed.orderedIDs.map {
            AppRecord(bundleIdentifier: $0, bundlePath: "/Applications/\($0).app", displayName: $0 == "notes" ? "Notes" : "Mail")
        }
        XCTAssertEqual(SearchMatcher.filter(apps, query: "mai").map(\.id), ["mail"])
    }

    func testEscapeClosesTheFolderBeforeTheGrid() {
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 53, characters: "", modifiers: [], isSearching: true, columns: 7, folderIsOpen: true),
            .clearSearch
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 53, characters: "", modifiers: [], isSearching: false, columns: 7, folderIsOpen: true),
            .closeFolder
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 53, characters: "", modifiers: [], isSearching: false, columns: 7, folderIsOpen: false),
            .dismiss
        )
    }

    func testFolderRoundTripKeepsNameAndOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gridback-folder-save-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PersistenceStore(directoryURL: directory)
        let grouped = FolderEditing.group(
            layout: Layout(pages: [["a", "b", "c"]], metrics: twoByTwo),
            draggedAppID: "b",
            targetID: "a"
        )
        let named = FolderEditing.rename(layout: grouped, folderID: grouped.folders[0].id, name: "Tools")
        try store.save(PersistedState(layout: named, shortcut: .default))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.layout.folders.map(\.name), ["Tools"])
        XCTAssertEqual(loaded.layout.folders.map(\.appIDs), [["a", "b"]])
    }

    func testOnlyANewFolderReportsAnIdentifierToOpen() {
        let layout = Layout(pages: [["a", "b", "c"]], metrics: twoByTwo)
        let created = FolderEditing.group(layout: layout, draggedAppID: "b", targetID: "a")
        XCTAssertEqual(FolderEditing.createdFolderID(before: layout, after: created), created.folders[0].id)
        let added = FolderEditing.group(layout: created, draggedAppID: "c", targetID: created.folders[0].id)
        XCTAssertNil(FolderEditing.createdFolderID(before: created, after: added))
    }

    func testLeavingThePanelRequiresTheHysteresisMargin() {
        let inside = FolderPanelExit.hasLeft(x: 200, y: 200, minX: 100, minY: 100, maxX: 300, maxY: 300)
        let barelyOutside = FolderPanelExit.hasLeft(x: 310, y: 200, minX: 100, minY: 100, maxX: 300, maxY: 300)
        let pastRight = FolderPanelExit.hasLeft(x: 325, y: 200, minX: 100, minY: 100, maxX: 300, maxY: 300)
        let pastTop = FolderPanelExit.hasLeft(x: 200, y: 70, minX: 100, minY: 100, maxX: 300, maxY: 300)
        XCTAssertFalse(inside)
        XCTAssertFalse(barelyOutside)
        XCTAssertTrue(pastRight)
        XCTAssertTrue(pastTop)
    }

    func testTheDropSlotChoosesTheGapAndACancelledDragDoesNotSave() throws {
        let created = FolderEditing.group(
            layout: Layout(pages: [["a", "b", "c"]], metrics: twoByTwo),
            draggedAppID: "b",
            targetID: "a"
        )
        XCTAssertEqual(created.folders[0].appIDs, ["a", "b"])
        let atFront = FolderEditing.moveAppOut(layout: created, appID: "b", toPage: 0, toSlot: 0)
        let atEnd = FolderEditing.moveAppOut(layout: created, appID: "b", toPage: 0, toSlot: 2)
        XCTAssertEqual(atFront.pages[0].map(\.id).first, "b")
        XCTAssertEqual(atEnd.pages[0].map(\.id).last, "b")
        XCTAssertNotEqual(atFront.orderedIDs, atEnd.orderedIDs)
        XCTAssertFalse(atFront.folders[0].appIDs.contains("b"))
        XCTAssertEqual(created.folders[0].appIDs, ["a", "b"])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gridback-folder-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PersistenceStore(directoryURL: directory)
        try store.save(PersistedState(layout: atEnd, shortcut: .default))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.layout.orderedIDs, atEnd.orderedIDs)
        XCTAssertEqual(loaded.layout.folders[0].appIDs, ["a"])
        XCTAssertEqual(loaded.layout.pages[0].map(\.id).last, "b")
    }
}
