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
        XCTAssertEqual(loaded.layout.orderedIDs, ["a", "b", "c"])
    }
}
