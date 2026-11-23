import XCTest
import GridBackCore

final class FolderExplainerTests: XCTestCase {
    func testExplainerIsOfferedOncePerAskablePlace() {
        for place in WallpaperPathPlace.allCases {
            var session = FolderExplainerSession()
            let kinds: [FolderVolumeKind] = place == .volumes ? [.none, .removable, .network, .fixed] : [.none]
            for volumeKind in kinds {
                let step = session.note(place: place, volumeKind: volumeKind, gridClosed: true, dragActive: false)
                let askable = FolderAccessRules.askable.contains(place)
                    && volumeKind != .network
                    && volumeKind != .fixed
                if askable {
                    XCTAssertEqual(step, .show(place), "place=\(place.rawValue) volume=\(volumeKind.rawValue)")
                    XCTAssertEqual(session.pending, place)
                    XCTAssertTrue(session.visible)
                    XCTAssertTrue(session.asked.isEmpty, "place=\(place.rawValue)")
                } else {
                    XCTAssertEqual(step, .idle, "place=\(place.rawValue) volume=\(volumeKind.rawValue)")
                    XCTAssertNil(session.pending)
                    XCTAssertFalse(session.visible)
                }
            }
        }
    }

    func testAllowAndNotNowRecordTheAskAndOnlyAllowReads() {
        var allowed = FolderExplainerSession()
        XCTAssertEqual(allowed.note(place: .downloads, gridClosed: true, dragActive: false), .show(.downloads))
        let allow = allowed.allow()
        XCTAssertEqual(allow?.place, .downloads)
        XCTAssertEqual(allow?.readAfter, true)
        XCTAssertEqual(allow?.asked, [.downloads])
        XCTAssertEqual(allow?.granted, [])
        XCTAssertNil(allowed.pending)
        XCTAssertFalse(allowed.visible)
        XCTAssertEqual(allowed.lastRead(for: .downloads), .unknown)
        XCTAssertEqual(allowed.note(place: .downloads, gridClosed: true, dragActive: false), .idle)

        allowed.noteGranted(.downloads)
        XCTAssertEqual(allowed.grantedList, [.downloads])
        XCTAssertEqual(allowed.lastRead(for: .downloads), .granted)
        XCTAssertEqual(allowed.note(place: .downloads, gridClosed: true, dragActive: false), .idle)
        allowed.noteGranted(.photosLibrary)
        allowed.noteGranted(.desktop)
        XCTAssertEqual(allowed.grantedList, [.downloads])

        var declined = FolderExplainerSession()
        XCTAssertEqual(declined.note(place: .desktop, gridClosed: true, dragActive: false), .show(.desktop))
        let notNow = declined.notNow()
        XCTAssertEqual(notNow?.readAfter, false)
        XCTAssertEqual(notNow?.asked, [.desktop])
        XCTAssertEqual(notNow?.granted, [])
        XCTAssertEqual(declined.note(place: .desktop, gridClosed: true, dragActive: false), .idle)
        XCTAssertNil(declined.allow())
        XCTAssertNil(declined.notNow())

        var refused = FolderExplainerSession(asked: [.documents], granted: [.documents])
        refused.noteDenied(.documents)
        XCTAssertEqual(refused.askedList, [.documents])
        XCTAssertEqual(refused.grantedList, [])
        XCTAssertEqual(refused.note(place: .documents, gridClosed: true, dragActive: false), .idle)
        XCTAssertEqual(refused.lastRead(for: .documents), .unknown)
    }

    func testNotNowRecordsThePlaceAndLeavesOtherGrants() {
        var session = FolderExplainerSession(asked: [.downloads], granted: [.downloads])
        XCTAssertEqual(session.note(place: .icloud, gridClosed: true, dragActive: false), .show(.icloud))
        let notNow = session.notNow()
        XCTAssertEqual(notNow?.readAfter, false)
        XCTAssertEqual(notNow?.asked, [.downloads, .icloud])
        XCTAssertEqual(notNow?.granted, [.downloads])
        XCTAssertEqual(session.note(place: .icloud, gridClosed: true, dragActive: false), .idle)
        XCTAssertEqual(session.note(place: .downloads, gridClosed: true, dragActive: false), .idle)
        XCTAssertEqual(session.lastRead(for: .downloads), .granted)
    }

    func testTimingHoldsTheOfferWhileTheGridIsOpenOrADragIsActive() {
        let samples: [(closed: Bool, drag: Bool, step: FolderExplainerStep)] = [
            (true, false, .show(.downloads)),
            (false, false, .wait(.downloads)),
            (true, true, .wait(.downloads)),
            (false, true, .wait(.downloads))
        ]
        for sample in samples {
            var session = FolderExplainerSession()
            let step = session.note(
                place: .downloads,
                gridClosed: sample.closed,
                dragActive: sample.drag
            )
            XCTAssertEqual(step, sample.step)
            XCTAssertEqual(session.visible, sample.step == .show(.downloads))
            XCTAssertTrue(session.asked.isEmpty)
        }
    }

    func testPendingExplainerWaitsUntilTheGridCloses() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.note(place: .documents, gridClosed: true, dragActive: false), .show(.documents))
        XCTAssertEqual(session.gridOpened(), .wait(.documents))
        XCTAssertFalse(session.visible)
        XCTAssertEqual(session.pending, .documents)
        XCTAssertTrue(session.asked.isEmpty)
        XCTAssertEqual(session.gridClosed(dragActive: true), .wait(.documents))
        XCTAssertEqual(session.dragEnded(gridClosed: false), .wait(.documents))
        XCTAssertEqual(session.gridClosed(dragActive: false), .show(.documents))
        XCTAssertTrue(session.visible)
        XCTAssertTrue(session.asked.isEmpty)

        let answer = session.notNow()
        XCTAssertEqual(answer?.asked, [.documents])
        XCTAssertEqual(session.gridClosed(dragActive: false), .idle)
        XCTAssertEqual(session.gridOpened(), .idle)
        XCTAssertNil(session.pending)
    }

    func testDragEndShowsAPendingOfferOnlyAfterTheGridIsClosed() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.note(place: .volumes, volumeKind: .removable, gridClosed: true, dragActive: true), .wait(.volumes))
        XCTAssertEqual(session.dragEnded(gridClosed: true), .show(.volumes))
        XCTAssertEqual(session.gridOpened(), .wait(.volumes))
        XCTAssertEqual(session.dragEnded(gridClosed: false), .wait(.volumes))
        XCTAssertTrue(session.asked.isEmpty)
        XCTAssertEqual(session.allow()?.readAfter, true)
        XCTAssertEqual(session.dragEnded(gridClosed: true), .idle)
    }

    func testAWallpaperChangeDropsAnUnansweredOffer() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.note(place: .desktop, gridClosed: true, dragActive: false), .show(.desktop))
        XCTAssertEqual(session.gridOpened(), .wait(.desktop))
        XCTAssertEqual(session.clearUnanswered(), .idle)
        XCTAssertNil(session.pending)
        XCTAssertTrue(session.asked.isEmpty)
        XCTAssertEqual(session.gridClosed(dragActive: false), .idle)
        XCTAssertEqual(session.note(place: .desktop, gridClosed: true, dragActive: false), .show(.desktop))
    }

    func testAnIdleSessionDoesNotRecordAnAnswer() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.gridOpened(), .idle)
        XCTAssertEqual(session.gridClosed(dragActive: false), .idle)
        XCTAssertEqual(session.dragEnded(gridClosed: true), .idle)
        XCTAssertNil(session.allow())
        XCTAssertNil(session.notNow())
        XCTAssertTrue(session.asked.isEmpty)
    }

    func testExplainerSizeStaysCompactOnEveryShow() {
        let width = FolderExplainerLayout.width
        let fitted = FolderExplainerLayout.size(measuredWidth: width, measuredHeight: 220)
        XCTAssertEqual(fitted, FolderExplainerSize(width: width, height: 220))

        let collapsed = FolderExplainerLayout.size(measuredWidth: 28, measuredHeight: 960)
        XCTAssertEqual(collapsed.width, width)
        XCTAssertEqual(collapsed.height, FolderExplainerLayout.minimumHeight)

        let huge = FolderExplainerLayout.size(measuredWidth: width, measuredHeight: 1_400)
        XCTAssertEqual(huge.width, width)
        XCTAssertEqual(huge.height, FolderExplainerLayout.maximumHeight)

        let empty = FolderExplainerLayout.size(measuredWidth: 0, measuredHeight: 0)
        XCTAssertEqual(empty, FolderExplainerSize(width: width, height: FolderExplainerLayout.minimumHeight))
    }

    func testShortcutDuringTheSystemPromptIsDropped() {
        XCTAssertEqual(FolderPromptHotkey.action(systemPromptWaiting: true), .drop)
        XCTAssertEqual(FolderPromptHotkey.action(systemPromptWaiting: false), .perform)
    }

    func testPlacePhraseForEveryPlaceAndTheBodyHasNoPath() {
        let phrases: [WallpaperPathPlace: String] = [
            .desktop: "on your Desktop",
            .documents: "in your Documents folder",
            .downloads: "in your Downloads folder",
            .icloud: "in iCloud Drive",
            .volumes: "on an external disk"
        ]
        for place in WallpaperPathPlace.allCases {
            let phrase = FolderExplainerCopy.placePhrase(place)
            XCTAssertEqual(phrase, phrases[place], "place=\(place.rawValue)")
            if phrases[place] == nil {
                XCTAssertNil(FolderExplainerCopy.body(place: place), "place=\(place.rawValue)")
                XCTAssertFalse(FolderExplainerCopy.promisesSystemPrompt(place), "place=\(place.rawValue)")
                continue
            }
            let body = FolderExplainerCopy.body(place: place) ?? ""
            XCTAssertTrue(body.contains(phrases[place] ?? ""), "place=\(place.rawValue)")
            XCTAssertTrue(body.contains("Nothing leaves your Mac."), "place=\(place.rawValue)")
            XCTAssertFalse(body.contains("/"), "place=\(place.rawValue)")
            XCTAssertFalse(body.contains("~"), "place=\(place.rawValue)")
            XCTAssertFalse(body.contains("\\"), "place=\(place.rawValue)")
            if place == .icloud {
                XCTAssertFalse(body.contains("macOS will ask"), "place=\(place.rawValue)")
                XCTAssertFalse(FolderExplainerCopy.promisesSystemPrompt(place))
            } else {
                XCTAssertTrue(body.contains("macOS will ask you to allow it."), "place=\(place.rawValue)")
                XCTAssertTrue(FolderExplainerCopy.promisesSystemPrompt(place))
            }
        }
        XCTAssertEqual(FolderExplainerCopy.title, "Show your wallpaper blurred behind your apps?")
        XCTAssertFalse(FolderExplainerCopy.title.contains("/"))
        XCTAssertFalse(FolderExplainerCopy.usageDescription.contains("/"))
    }

    func testHotkeyWhilePendingSuspendsRatherThanDeclines() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.note(place: .downloads, gridClosed: true, dragActive: false), .show(.downloads))
        XCTAssertEqual(session.gridOpened(), .wait(.downloads))
        XCTAssertEqual(session.pending, .downloads)
        XCTAssertTrue(session.asked.isEmpty)
        XCTAssertTrue(session.denied.isEmpty)
        XCTAssertEqual(session.gridClosed(dragActive: false), .show(.downloads))
    }

    func testCloseCountsAsNotNow() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.note(place: .desktop, gridClosed: true, dragActive: false), .show(.desktop))
        let closed = session.notNow()
        XCTAssertEqual(closed?.readAfter, false)
        XCTAssertEqual(closed?.asked, [.desktop])
        XCTAssertEqual(closed?.granted, [])
        XCTAssertEqual(session.note(place: .desktop, gridClosed: true, dragActive: false), .idle)
    }

    func testReofferShowsTheSamePlace() {
        var session = FolderExplainerSession()
        XCTAssertEqual(session.note(place: .documents, gridClosed: true, dragActive: false), .show(.documents))
        XCTAssertEqual(session.gridOpened(), .wait(.documents))
        XCTAssertEqual(session.gridClosed(dragActive: false), .show(.documents))
        XCTAssertEqual(session.pending, .documents)
        XCTAssertTrue(session.asked.isEmpty)
    }

    func testDeniedStateShowsNoExplainer() {
        var session = FolderExplainerSession(asked: [.downloads], denied: [.downloads])
        XCTAssertEqual(session.note(place: .downloads, gridClosed: true, dragActive: false), .idle)
        XCTAssertNil(session.pending)
        XCTAssertFalse(session.visible)

        var fresh = FolderExplainerSession()
        XCTAssertEqual(fresh.note(place: .downloads, gridClosed: true, dragActive: false), .show(.downloads))
        XCTAssertEqual(fresh.allow()?.readAfter, true)
        fresh.noteDenied(.downloads)
        XCTAssertEqual(fresh.deniedList, [.downloads])
        XCTAssertEqual(fresh.note(place: .downloads, gridClosed: true, dragActive: false), .idle)
        fresh.noteDenied(.photosLibrary)
        XCTAssertEqual(fresh.deniedList, [.downloads])
    }

    func testProtectedPictureIsChosenFromPathTextAlone() {
        let downloads = "/Users/example/Downloads/wall.jpg"
        let pictures = "/Users/example/Pictures/wall.jpg"
        let desktop = "/Users/example/Desktop/wall.jpg"
        XCTAssertEqual(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.imageProvider,
                isFolder: false,
                storePaths: [downloads],
                workspacePath: pictures,
                resolvedUseIsFile: false
            ),
            FolderWallpaperCandidate(path: downloads, place: .downloads)
        )
        XCTAssertNil(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.imageProvider,
                isFolder: false,
                storePaths: [pictures],
                workspacePath: desktop,
                resolvedUseIsFile: true
            )
        )
        XCTAssertNil(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.colorProvider,
                isFolder: false,
                storePaths: [],
                workspacePath: desktop,
                resolvedUseIsFile: false
            )
        )
        XCTAssertNil(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.aerialsProvider,
                isFolder: false,
                storePaths: [],
                workspacePath: desktop,
                resolvedUseIsFile: false
            )
        )
        XCTAssertNil(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.imageProvider,
                isFolder: true,
                storePaths: [downloads],
                workspacePath: nil,
                resolvedUseIsFile: false
            )
        )
        XCTAssertEqual(
            FolderAskTargeting.protectedPicture(
                provider: nil,
                isFolder: false,
                storePaths: [],
                workspacePath: desktop,
                resolvedUseIsFile: false
            )?.place,
            .desktop
        )
        XCTAssertNil(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.imageProvider,
                isFolder: false,
                storePaths: [pictures],
                workspacePath: desktop,
                resolvedUseIsFile: false
            )
        )
        let photos = "/Users/example/Pictures/Example.photoslibrary/wall.jpg"
        XCTAssertEqual(
            FolderAskTargeting.protectedPicture(
                provider: WallpaperStoreIndex.imageProvider,
                isFolder: false,
                storePaths: [photos],
                workspacePath: nil,
                resolvedUseIsFile: false
            )?.place,
            .photosLibrary
        )
    }

    func testProbeOpensAskablePlacesAndLeavesARemoteCloudFileClosed() {
        for place in WallpaperPathPlace.allCases {
            let local = FolderProbePlan.shouldOpen(place: place, alreadyLocal: true)
            let remote = FolderProbePlan.shouldOpen(place: place, alreadyLocal: false)
            if FolderAccessRules.askable.contains(place) {
                XCTAssertTrue(local, "place=\(place.rawValue)")
            } else {
                XCTAssertFalse(local, "place=\(place.rawValue)")
                XCTAssertFalse(remote, "place=\(place.rawValue)")
            }
        }
        XCTAssertFalse(FolderProbePlan.shouldOpen(place: .icloud, alreadyLocal: false))
        XCTAssertTrue(FolderProbePlan.shouldOpen(place: .icloud, alreadyLocal: true))
        XCTAssertTrue(FolderProbePlan.shouldOpen(place: .downloads, alreadyLocal: false))
        XCTAssertFalse(FolderProbePlan.shouldOpen(place: .photosLibrary, alreadyLocal: true))
    }

    func testGrantedPlacesRoundTripAndOlderSavesStillLoad() throws {
        XCTAssertEqual(PersistedState.grantedLocationsKey, "grantedLocations")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gridback-explainer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = PersistenceStore(directoryURL: directory)
        let state = PersistedState(
            layout: Layout(pages: [["com.apple.Safari"]], metrics: .classic),
            shortcut: .default,
            askedLocations: [.downloads, .desktop],
            grantedLocations: [.downloads, .pictures, .desktop, .photosLibrary]
        )
        try store.save(state)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.askedLocations, [.desktop, .downloads])
        XCTAssertEqual(loaded.grantedLocations, [.desktop, .downloads])
        let data = try Data(contentsOf: store.stateURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json[PersistedState.grantedLocationsKey] as? [String], ["desktop", "downloads"])

        let older = """
        {
          "layout" : {
            "metrics" : { "columns" : 7, "rows" : 5 },
            "pages" : [ ["a"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 2
        }
        """
        try Data(older.utf8).write(to: store.stateURL)
        let migrated = try XCTUnwrap(store.load())
        XCTAssertEqual(migrated.askedLocations, [])
        XCTAssertEqual(migrated.grantedLocations, [])
        XCTAssertEqual(migrated.deniedLocations, [])

        let grantWithoutAsk = """
        {
          "askedLocations" : ["downloads"],
          "grantedLocations" : ["desktop", "downloads", "made-up"],
          "layout" : {
            "metrics" : { "columns" : 7, "rows" : 5 },
            "pages" : [ ["a"] ]
          },
          "shortcut" : { "carbonModifiers" : 6144, "keyCode" : 5, "keyLabel" : "G" },
          "version" : 2
        }
        """
        try Data(grantWithoutAsk.utf8).write(to: store.stateURL)
        let cleaned = try XCTUnwrap(store.load())
        XCTAssertEqual(cleaned.askedLocations, [.downloads])
        XCTAssertEqual(cleaned.grantedLocations, [.downloads])

        var session = FolderExplainerSession(asked: cleaned.askedLocations, granted: cleaned.grantedLocations)
        XCTAssertEqual(session.note(place: .downloads, gridClosed: true, dragActive: false), .idle)
        XCTAssertEqual(session.lastRead(for: .downloads), .granted)
        XCTAssertEqual(session.note(place: .desktop, gridClosed: true, dragActive: false), .show(.desktop))

        let refused = PersistedState(
            layout: cleaned.layout,
            shortcut: cleaned.shortcut,
            askedLocations: [.downloads],
            deniedLocations: [.downloads, .system]
        )
        try store.save(refused)
        let refusedLoad = try XCTUnwrap(store.load())
        XCTAssertEqual(refusedLoad.deniedLocations, [.downloads])
        var refusedSession = FolderExplainerSession(
            asked: refusedLoad.askedLocations,
            denied: refusedLoad.deniedLocations
        )
        XCTAssertEqual(refusedSession.note(place: .downloads, gridClosed: true, dragActive: false), .idle)
    }
}
