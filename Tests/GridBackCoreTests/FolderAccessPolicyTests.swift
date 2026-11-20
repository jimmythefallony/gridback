import XCTest
import GridBackCore

final class FolderAccessPolicyTests: XCTestCase {
    func testExclusionsLiveInOneRuleList() {
        XCTAssertEqual(
            FolderAccessRules.askable,
            [.desktop, .documents, .downloads, .icloud, .volumes]
        )
        XCTAssertEqual(FolderAccessRules.neverAskVolumeKinds, [.network])
        XCTAssertEqual(FolderAccessRules.neverDownload, [.icloud])
        XCTAssertFalse(FolderAccessRules.askable.contains(.photosLibrary))
        XCTAssertFalse(FolderAccessRules.askable.contains(.system))
        XCTAssertFalse(FolderAccessRules.askable.contains(.pictures))
        for place in WallpaperPathPlace.allCases {
            XCTAssertEqual(FolderAccessRules.allowsDownload(place), place != .icloud)
        }
    }

    func testEveryPlaceAskedFlagAndReadResult() {
        let reads: [FolderReadResult] = [.granted, .denied, .unknown]
        for place in WallpaperPathPlace.allCases {
            let kinds: [FolderVolumeKind] = place == .volumes ? [.none, .removable, .network] : [.none]
            for volumeKind in kinds {
                for asked in [false, true] {
                    for lastRead in reads {
                        let askedLocations: Set<WallpaperPathPlace> = asked ? [place] : []
                        let decision = FolderAccessPolicy.decide(
                            place: place,
                            askedLocations: askedLocations,
                            lastRead: lastRead,
                            volumeKind: volumeKind
                        )
                        let expected = expectedDecision(
                            place: place,
                            asked: asked,
                            lastRead: lastRead,
                            volumeKind: volumeKind
                        )
                        XCTAssertEqual(
                            decision,
                            expected,
                            "place=\(place.rawValue) asked=\(asked) read=\(lastRead.rawValue) volume=\(volumeKind.rawValue)"
                        )
                        if place == .photosLibrary || place == .system || volumeKind == .network {
                            XCTAssertNotEqual(decision, .offerAsk, "place=\(place.rawValue)")
                        }
                        if place.isProtected, !asked {
                            XCTAssertNotEqual(decision, .tryRead, "place=\(place.rawValue)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(
            FolderAccessPolicy.decide(
                place: .desktop,
                askedLocations: [],
                lastRead: .unknown,
                volumeKind: .network
            ),
            .offerAsk
        )
    }

    func testProtectedUnaskedPathsAreNeverTouched() {
        let reads: [FolderReadResult] = [.granted, .denied, .unknown]
        let modified = Date(timeIntervalSince1970: 10)
        let later = Date(timeIntervalSince1970: 20)
        for path in protectedSamples {
            let place = WallpaperPathPlace.classify(path)
            XCTAssertTrue(place.isProtected, "place=\(place.rawValue)")
            let kinds: [FolderVolumeKind] = place == .volumes ? [.none, .removable, .network] : [.none]
            for volumeKind in kinds {
                for lastRead in reads {
                    for appBecameActive in [false, true] {
                        for stamp in [modified, later, nil] as [Date?] {
                            var denial = FolderDenialCache()
                            denial.store(path: path, modified: modified)
                            let accessor = ExplodingAccessor()
                            let decision = FolderFileAttempt.perform(
                                path: path,
                                askedLocations: [],
                                lastRead: lastRead,
                                volumeKind: volumeKind,
                                denial: denial,
                                modified: stamp,
                                appBecameActive: appBecameActive,
                                accessor: accessor
                            )
                            XCTAssertNotEqual(decision, .tryRead, "place=\(place.rawValue)")
                            XCTAssertEqual(accessor.calls, 0, "place=\(place.rawValue)")
                            XCTAssertTrue(WallpaperFileGate.plan(paths: [path]).statPaths.isEmpty, "place=\(place.rawValue)")
                        }
                    }
                }
            }
        }
    }

    func testAllowedReadTouchesOnlyAfterThePolicySaysSo() {
        let pictures = "/Users/example/Pictures/wall.jpg"
        let open = RecordingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: pictures,
                askedLocations: [],
                lastRead: .unknown,
                accessor: open
            ),
            .tryRead
        )
        XCTAssertEqual(open.operations, FolderFileOperation.all)

        let desktop = "/Users/example/Desktop/wall.jpg"
        let granted = RecordingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: desktop,
                askedLocations: [.desktop],
                lastRead: .granted,
                accessor: granted
            ),
            .tryRead
        )
        XCTAssertEqual(granted.operations, FolderFileOperation.all)
        XCTAssertTrue(granted.calls.allSatisfy(\.allowingDownload))

        let icloud = "/Users/example/Library/Mobile Documents/wall.jpg"
        let cloud = RecordingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: icloud,
                askedLocations: [.icloud],
                lastRead: .granted,
                accessor: cloud
            ),
            .tryRead
        )
        XCTAssertEqual(cloud.operations, FolderFileOperation.all)
        XCTAssertTrue(cloud.calls.allSatisfy { !$0.allowingDownload })
    }

    func testNotNowAndFreshDenialDoNotTouch() {
        let desktop = "/Users/example/Desktop/wall.jpg"
        let modified = Date(timeIntervalSince1970: 10)
        var denial = FolderDenialCache()
        denial.store(path: desktop, modified: modified)

        let notNow = ExplodingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: desktop,
                askedLocations: [.desktop],
                lastRead: .unknown,
                denial: denial,
                modified: modified,
                appBecameActive: true,
                accessor: notNow
            ),
            .fallback
        )
        XCTAssertEqual(notNow.calls, 0)

        let fresh = ExplodingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: desktop,
                askedLocations: [.desktop],
                lastRead: .denied,
                denial: denial,
                modified: modified,
                appBecameActive: false,
                accessor: fresh
            ),
            .fallback
        )
        XCTAssertEqual(fresh.calls, 0)

        let photos = "/Users/example/Pictures/Example.photoslibrary/wall.jpg"
        let library = ExplodingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: photos,
                askedLocations: [.photosLibrary],
                lastRead: .granted,
                denial: denial,
                modified: modified,
                appBecameActive: true,
                accessor: library
            ),
            .doNotTouch
        )
        XCTAssertEqual(library.calls, 0)

        let network = ExplodingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: "/Volumes/Example/wall.jpg",
                askedLocations: [.volumes],
                lastRead: .granted,
                volumeKind: .network,
                appBecameActive: true,
                accessor: network
            ),
            .doNotTouch
        )
        XCTAssertEqual(network.calls, 0)
    }

    func testDeniedReadIsRetriedOnlyWhenTheWallpaperChangesOrTheAppBecomesActive() {
        let first = "/Users/example/Pictures/wall.jpg"
        let second = "/Users/example/Pictures/other.jpg"
        let modified = Date(timeIntervalSince1970: 10)
        let changed = Date(timeIntervalSince1970: 20)
        var denial = FolderDenialCache()
        denial.store(path: first, modified: modified)

        XCTAssertFalse(denial.shouldRetry(path: first, modified: modified, appBecameActive: false))
        XCTAssertTrue(denial.shouldRetry(path: first, modified: changed, appBecameActive: false))
        XCTAssertTrue(denial.shouldRetry(path: first, modified: modified, appBecameActive: true))
        XCTAssertTrue(denial.shouldRetry(path: second, modified: modified, appBecameActive: false))
        XCTAssertFalse(FolderDenialCache().shouldRetry(path: first, modified: modified, appBecameActive: true))

        denial.store(path: second, modified: nil)
        XCTAssertFalse(denial.shouldRetry(path: second, modified: nil, appBecameActive: false))
        XCTAssertTrue(denial.shouldRetry(path: second, modified: changed, appBecameActive: false))
        XCTAssertFalse(denial.shouldRetry(path: first, modified: modified, appBecameActive: false))

        let blocked = ExplodingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: first,
                askedLocations: [],
                lastRead: .denied,
                denial: denial,
                modified: modified,
                appBecameActive: false,
                accessor: blocked
            ),
            .fallback
        )
        XCTAssertEqual(blocked.calls, 0)

        let active = RecordingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: first,
                askedLocations: [],
                lastRead: .denied,
                denial: denial,
                modified: modified,
                appBecameActive: true,
                accessor: active
            ),
            .tryRead
        )
        XCTAssertEqual(active.operations, FolderFileOperation.all)

        let moved = RecordingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: first,
                askedLocations: [],
                lastRead: .denied,
                denial: denial,
                modified: changed,
                accessor: moved
            ),
            .tryRead
        )
        XCTAssertEqual(moved.operations, FolderFileOperation.all)

        let desktop = "/Users/example/Desktop/wall.jpg"
        var askedDenial = FolderDenialCache()
        askedDenial.store(path: desktop, modified: modified)
        let again = RecordingAccessor()
        XCTAssertEqual(
            FolderFileAttempt.perform(
                path: desktop,
                askedLocations: [.desktop],
                lastRead: .denied,
                denial: askedDenial,
                modified: changed,
                accessor: again
            ),
            .tryRead
        )
        XCTAssertEqual(again.operations, FolderFileOperation.all)

        XCTAssertEqual(
            FolderAccessPolicy.applying(.offerAsk, lastRead: .denied, shouldRetryDenied: true),
            .offerAsk
        )
        XCTAssertEqual(
            FolderAccessPolicy.applying(.doNotTouch, lastRead: .denied, shouldRetryDenied: true),
            .doNotTouch
        )
        XCTAssertEqual(
            FolderAccessPolicy.applying(.fallback, lastRead: .unknown, shouldRetryDenied: true),
            .fallback
        )
        XCTAssertEqual(
            FolderAccessPolicy.applying(.tryRead, lastRead: .granted, shouldRetryDenied: false),
            .tryRead
        )
    }

    func testAskIsOfferedOnlyWhenTheGridIsClosedAndNoDragIsActive() {
        XCTAssertTrue(FolderAskTiming.mayOffer(gridClosed: true, dragActive: false))
        XCTAssertFalse(FolderAskTiming.mayOffer(gridClosed: false, dragActive: false))
        XCTAssertFalse(FolderAskTiming.mayOffer(gridClosed: true, dragActive: true))
        XCTAssertFalse(FolderAskTiming.mayOffer(gridClosed: false, dragActive: true))
        XCTAssertFalse(
            FolderAccessPolicy.decide(place: .downloads, askedLocations: [], lastRead: .unknown) == .offerAsk
                && FolderAskTiming.mayOffer(gridClosed: false, dragActive: false)
        )
        XCTAssertTrue(
            FolderAccessPolicy.decide(place: .downloads, askedLocations: [], lastRead: .unknown) == .offerAsk
                && FolderAskTiming.mayOffer(gridClosed: true, dragActive: false)
        )
    }

    func testAccessLogUsesThePlaceNameOnly() {
        let line = FolderAccessLog.line(place: .downloads, decision: .offerAsk)
        XCTAssertEqual(line, "place=downloads decision=offerAsk")
        XCTAssertFalse(line.contains("/"))
        XCTAssertFalse(line.contains("~"))
        XCTAssertFalse(line.contains("\\"))
        for place in WallpaperPathPlace.allCases {
            let logged = FolderAccessLog.line(place: place, decision: .fallback)
            XCTAssertTrue(logged.hasPrefix("place=\(place.rawValue) "))
            XCTAssertFalse(logged.contains("/"))
            XCTAssertFalse(logged.contains("~"))
        }
    }

    func testAskedLocationsRoundTripAndMigration() throws {
        XCTAssertEqual(PersistedState.askedLocationsKey, "askedLocations")
        let directory = try makeDirectory()
        let store = PersistenceStore(directoryURL: directory)
        let state = PersistedState(
            layout: Layout(pages: [["com.apple.Safari"]], metrics: .classic),
            shortcut: .default,
            askedLocations: [.downloads, .desktop, .downloads, .pictures, .photosLibrary, .system]
        )
        try store.save(state)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.askedLocations, [.desktop, .downloads])
        XCTAssertEqual(loaded, state.repaired())

        let data = try Data(contentsOf: store.stateURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json[PersistedState.askedLocationsKey] as? [String], ["desktop", "downloads"])

        let missing = """
        {
          "layout" : {
            "metrics" : { "columns" : 7, "rows" : 5 },
            "pages" : [ ["a"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 2
        }
        """
        try Data(missing.utf8).write(to: store.stateURL)
        let migrated = try XCTUnwrap(store.load())
        XCTAssertEqual(migrated.askedLocations, [])
        XCTAssertEqual(migrated.version, 2)
        try store.save(migrated)
        let rewritten = try Data(contentsOf: store.stateURL)
        let rewrittenJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        XCTAssertEqual(rewrittenJSON[PersistedState.askedLocationsKey] as? [String], [])

        let messy = """
        {
          "askedLocations" : ["downloads", "made-up", "system", "downloads", null, "icloud"],
          "layout" : {
            "metrics" : { "columns" : 7, "rows" : 5 },
            "pages" : [ ["a"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 1
        }
        """
        try Data(messy.utf8).write(to: store.stateURL)
        let cleaned = try XCTUnwrap(store.load())
        XCTAssertEqual(cleaned.askedLocations, [.downloads, .icloud])
        XCTAssertEqual(cleaned.version, 2)

        let empty = """
        {
          "askedLocations" : null,
          "layout" : {
            "metrics" : { "columns" : 7, "rows" : 5 },
            "pages" : [ ["a"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 2
        }
        """
        try Data(empty.utf8).write(to: store.stateURL)
        XCTAssertEqual(try store.load()?.askedLocations, [])
    }

    private func expectedDecision(
        place: WallpaperPathPlace,
        asked: Bool,
        lastRead: FolderReadResult,
        volumeKind: FolderVolumeKind
    ) -> FolderAccessDecision {
        if place == .volumes, volumeKind == .network {
            return .doNotTouch
        }
        switch place {
        case .photosLibrary:
            return .doNotTouch
        case .pictures, .system, .other:
            return lastRead == .denied ? .fallback : .tryRead
        case .desktop, .documents, .downloads, .icloud, .volumes:
            if !asked { return .offerAsk }
            return lastRead == .granted ? .tryRead : .fallback
        }
    }

    private var protectedSamples: [String] {
        [
            "/Users/example/Desktop/wall.jpg",
            "~/Desktop/wall.jpg",
            "file:///Users/example/Desktop/wall.jpg",
            "/Users/example/Documents/wall.jpg",
            "/Users/example/Downloads/wall.jpg",
            "/Users/example/Pictures/Example.photoslibrary/wall.jpg",
            "/Users/example/Library/Mobile Documents/wall.jpg",
            "~/Library/Mobile Documents/wall.jpg",
            "/Volumes/Example/wall.jpg",
            "/Library/Example/../../Users/example/Desktop/wall.jpg"
        ]
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gridback-folder-access-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private enum FolderFileOperation {
    static let all = ["fileExists", "stat", "resourceValues", "list", "readImage"]
}

private struct FileTouch: Equatable {
    var operation: String
    var allowingDownload: Bool
}

private final class RecordingAccessor: FolderFileAccessor {
    var calls: [FileTouch] = []

    var operations: [String] { calls.map(\.operation) }

    func fileExists(at path: String, allowingDownload: Bool) {
        calls.append(FileTouch(operation: "fileExists", allowingDownload: allowingDownload))
    }

    func stat(at path: String, allowingDownload: Bool) {
        calls.append(FileTouch(operation: "stat", allowingDownload: allowingDownload))
    }

    func resourceValues(at path: String, allowingDownload: Bool) {
        calls.append(FileTouch(operation: "resourceValues", allowingDownload: allowingDownload))
    }

    func list(at path: String, allowingDownload: Bool) {
        calls.append(FileTouch(operation: "list", allowingDownload: allowingDownload))
    }

    func readImage(at path: String, allowingDownload: Bool) {
        calls.append(FileTouch(operation: "readImage", allowingDownload: allowingDownload))
    }
}

private final class ExplodingAccessor: FolderFileAccessor {
    var calls = 0

    func fileExists(at path: String, allowingDownload: Bool) { fail("fileExists") }
    func stat(at path: String, allowingDownload: Bool) { fail("stat") }
    func resourceValues(at path: String, allowingDownload: Bool) { fail("resourceValues") }
    func list(at path: String, allowingDownload: Bool) { fail("list") }
    func readImage(at path: String, allowingDownload: Bool) { fail("readImage") }

    private func fail(_ operation: String) {
        calls += 1
        XCTFail(operation)
    }
}
