import XCTest
import GridBackCore

final class PersistenceStoreTests: XCTestCase {
    func testRoundTripAndAtomicReplace() throws {
        let directory = try makeDirectory()
        let store = PersistenceStore(directoryURL: directory)
        XCTAssertNil(try store.load())

        let first = PersistedState(
            layout: Layout(pages: [["com.apple.Safari", "com.apple.Mail"]], metrics: .classic),
            shortcut: .default
        )
        try store.save(first)
        XCTAssertEqual(try store.load(), first.repaired())

        let second = PersistedState(
            layout: Layout(pages: [["com.apple.Mail"], ["com.apple.Safari"]], metrics: GridMetrics(columns: 7, rows: 5)),
            shortcut: ShortcutChord(keyCode: 15, carbonModifiers: ShortcutChord.commandModifier, keyLabel: "R")
        )
        try store.save(second)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded, second.repaired())
        XCTAssertEqual(loaded.shortcut.displayString, "⌘R")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(".state-leftover.tmp").path))
        let leftovers = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(leftovers.map(\.lastPathComponent), ["state.json"])
    }

    func testCorruptFileThrowsAndCanBeQuarantined() throws {
        let directory = try makeDirectory()
        let store = PersistenceStore(directoryURL: directory)
        try Data("not json".utf8).write(to: store.stateURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case PersistenceError.unreadable = error else {
                return XCTFail("expected unreadable, got \(error)")
            }
        }
        let quarantined = try XCTUnwrap(store.quarantineStateFile(now: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertEqual(quarantined.lastPathComponent, "state.json.unreadable-1700000000")
        XCTAssertNil(try store.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantined.path))
    }

    func testUnsupportedVersionThrows() throws {
        let directory = try makeDirectory()
        let store = PersistenceStore(directoryURL: directory)
        let body = """
        {"layout":{"metrics":{"columns":7,"rows":5},"pages":[]},"shortcut":{"carbonModifiers":6144,"keyCode":5,"keyLabel":"G"},"version":99}
        """
        try Data(body.utf8).write(to: store.stateURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? PersistenceError, .unsupportedVersion(99))
        }
    }

    func testLoadRepairsDuplicateIDs() throws {
        let directory = try makeDirectory()
        let store = PersistenceStore(directoryURL: directory)
        let body = """
        {
          "layout" : {
            "metrics" : { "columns" : 2, "rows" : 2 },
            "pages" : [ ["a", "b", "a"], ["c"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 1
        }
        """
        try Data(body.utf8).write(to: store.stateURL)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.layout.pages, [["a", "b"], ["c"]])
        XCTAssertEqual(loaded.shortcut, .default)
    }

    func testDefaultShortcutIsControlOptionG() {
        XCTAssertEqual(ShortcutChord.default.displayString, "⌃⌥G")
        XCTAssertNil(ShortcutChord.default.rejection())
        XCTAssertEqual(
            ShortcutChord(keyCode: 15, carbonModifiers: 0, keyLabel: "R").rejection(),
            .needsModifier
        )
        XCTAssertEqual(
            ShortcutChord(keyCode: 55, carbonModifiers: ShortcutChord.commandModifier, keyLabel: "⌘").rejection(),
            .modifierKeyOnly
        )
        XCTAssertEqual(ShortcutFormatting.label(forKeyCode: 122, characters: ""), "F1")
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gridback-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
