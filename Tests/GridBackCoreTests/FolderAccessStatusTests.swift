import XCTest
import GridBackCore

final class FolderAccessStatusTests: XCTestCase {
    func testStatusTableAcrossPlaceVolumeAndSavedFlags() {
        let reads: [FolderReadResult] = [.unknown, .granted, .denied]
        for place in WallpaperPathPlace.allCases {
            for volumeKind in FolderVolumeKind.allCases {
                for asked in [false, true] {
                    for granted in [false, true] {
                        for denied in [false, true] {
                            for lastRead in reads {
                                let status = FolderAccessStatus.make(
                                    place: place,
                                    volumeKind: volumeKind,
                                    asked: asked,
                                    granted: granted,
                                    denied: denied,
                                    lastRead: lastRead
                                )
                                let expected = expectedStatus(
                                    place: place,
                                    volumeKind: volumeKind,
                                    asked: asked,
                                    granted: granted,
                                    denied: denied,
                                    lastRead: lastRead
                                )
                                XCTAssertEqual(
                                    status,
                                    expected,
                                    "place=\(place.rawValue) volume=\(volumeKind.rawValue) asked=\(asked) granted=\(granted) denied=\(denied) read=\(lastRead.rawValue)"
                                )
                                XCTAssertEqual(
                                    FolderAccessStatus.mayProbeSilently(status),
                                    status == .allowed || status == .notAllowed,
                                    "place=\(place.rawValue) status=\(status.rawValue)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testNotableRows() {
        XCTAssertEqual(status(.pictures, .none, false, false, false, .unknown), .notNeeded)
        XCTAssertEqual(status(.system, .none, true, true, true, .denied), .notNeeded)
        XCTAssertEqual(status(.other, .network, false, false, true, .denied), .notNeeded)
        XCTAssertEqual(status(.icloud, .none, false, false, false, .unknown), .notNeeded)
        XCTAssertEqual(status(.icloud, .none, true, false, true, .denied), .notNeeded)
        XCTAssertEqual(status(.volumes, .fixed, false, false, false, .unknown), .notNeeded)
        XCTAssertEqual(status(.volumes, .fixed, true, false, true, .denied), .notNeeded)
        XCTAssertEqual(status(.photosLibrary, .none, false, false, false, .unknown), .unsupported)
        XCTAssertEqual(status(.photosLibrary, .none, true, true, false, .granted), .unsupported)
        XCTAssertEqual(status(.volumes, .network, true, true, false, .granted), .unsupported)
        XCTAssertEqual(status(.desktop, .none, false, false, false, .unknown), .notAsked)
        XCTAssertEqual(status(.downloads, .none, true, false, false, .unknown), .notNow)
        XCTAssertEqual(status(.documents, .none, true, true, false, .granted), .allowed)
        XCTAssertEqual(status(.desktop, .none, true, true, false, .denied), .notAllowed)
        XCTAssertEqual(status(.desktop, .none, true, false, true, .unknown), .notAllowed)
        XCTAssertEqual(status(.volumes, .removable, false, false, false, .unknown), .notAsked)
        XCTAssertEqual(status(.volumes, .none, true, false, false, .unknown), .notNow)
    }

    private func status(
        _ place: WallpaperPathPlace,
        _ volumeKind: FolderVolumeKind,
        _ asked: Bool,
        _ granted: Bool,
        _ denied: Bool,
        _ lastRead: FolderReadResult
    ) -> FolderAccessStatus {
        FolderAccessStatus.make(
            place: place,
            volumeKind: volumeKind,
            asked: asked,
            granted: granted,
            denied: denied,
            lastRead: lastRead
        )
    }

    func testMayProbeSilentlyOnlyForAllowedAndNotAllowed() {
        for status in FolderAccessStatus.allCases {
            let probe = FolderAccessStatus.mayProbeSilently(status)
            switch status {
            case .allowed, .notAllowed:
                XCTAssertTrue(probe, status.rawValue)
            case .notNeeded, .notAsked, .notNow, .unsupported:
                XCTAssertFalse(probe, status.rawValue)
            }
        }
    }

    func testAskAgainTurnsNotNowIntoNotAskedAndLeavesNotAllowed() {
        let notNow = FolderAccessEdits.askAgain(
            place: .desktop,
            volumeKind: .none,
            asked: [.desktop, .downloads],
            granted: [.downloads],
            denied: [],
            lastRead: .unknown
        )
        XCTAssertEqual(
            FolderAccessStatus.make(
                place: .desktop,
                volumeKind: .none,
                asked: true,
                granted: false,
                denied: false,
                lastRead: .unknown
            ),
            .notNow
        )
        XCTAssertEqual(notNow.asked, [.downloads])
        XCTAssertEqual(notNow.granted, [.downloads])
        XCTAssertEqual(notNow.denied, [])
        XCTAssertEqual(
            FolderAccessStatus.make(
                place: .desktop,
                volumeKind: .none,
                asked: notNow.asked.contains(.desktop),
                granted: notNow.granted.contains(.desktop),
                denied: notNow.denied.contains(.desktop),
                lastRead: .unknown
            ),
            .notAsked
        )

        let refused = FolderAccessLists(asked: [.downloads], granted: [], denied: [.downloads])
        let stillRefused = FolderAccessEdits.askAgain(
            place: .downloads,
            volumeKind: .none,
            asked: refused.asked,
            granted: refused.granted,
            denied: refused.denied,
            lastRead: .denied
        )
        XCTAssertEqual(stillRefused, refused)
        XCTAssertEqual(
            FolderAccessStatus.make(
                place: .downloads,
                volumeKind: .none,
                asked: true,
                granted: false,
                denied: true,
                lastRead: .denied
            ),
            .notAllowed
        )

        let failedRead = FolderAccessLists(asked: [.documents], granted: [.documents], denied: [])
        let stillFailed = FolderAccessEdits.askAgain(
            place: .documents,
            volumeKind: .none,
            asked: failedRead.asked,
            granted: failedRead.granted,
            denied: failedRead.denied,
            lastRead: .denied
        )
        XCTAssertEqual(stillFailed, failedRead)
    }

    func testSuccessfulRecheckMovesDeniedToGrantedAndClearsTheCachedDenial() {
        let path = "/Users/example/Desktop/wall.jpg"
        let other = "/Users/example/Downloads/wall.jpg"
        let modified = Date(timeIntervalSince1970: 20)
        var denial = FolderDenialCache()
        denial.store(path: path, modified: modified)
        denial.store(path: other, modified: modified)

        let result = FolderAccessEdits.recheck(
            succeeded: true,
            place: .desktop,
            path: path,
            modified: modified,
            asked: [.desktop],
            granted: [],
            denied: [.desktop],
            denial: denial
        )
        XCTAssertEqual(result.lists.asked, [.desktop])
        XCTAssertEqual(result.lists.granted, [.desktop])
        XCTAssertEqual(result.lists.denied, [])
        XCTAssertEqual(result.denial.entries.map(\.path), [other])
        XCTAssertEqual(
            FolderAccessStatus.make(
                place: .desktop,
                volumeKind: .none,
                asked: true,
                granted: true,
                denied: false,
                lastRead: .granted
            ),
            .allowed
        )
    }

    func testFailedRecheckRecordsTheDenial() {
        let path = "/Users/example/Documents/wall.jpg"
        let result = FolderAccessEdits.recheck(
            succeeded: false,
            place: .documents,
            path: path,
            modified: nil,
            asked: [.documents],
            granted: [.documents],
            denied: [],
            denial: FolderDenialCache()
        )
        XCTAssertEqual(result.lists.asked, [.documents])
        XCTAssertEqual(result.lists.granted, [])
        XCTAssertEqual(result.lists.denied, [.documents])
        XCTAssertEqual(result.denial.entries.map(\.path), [path])
        XCTAssertEqual(
            FolderAccessStatus.make(
                place: .documents,
                volumeKind: .none,
                asked: true,
                granted: false,
                denied: true,
                lastRead: .denied
            ),
            .notAllowed
        )
    }

    func testActionsAndHintFollowTheLine() {
        for status in FolderAccessStatus.allCases {
            switch status {
            case .notAsked:
                XCTAssertEqual(FolderAccessStatusCopy.action(status), .allow)
                XCTAssertNil(FolderAccessStatusCopy.hint(for: status))
            case .notNow:
                XCTAssertEqual(FolderAccessStatusCopy.action(status), .askAgain)
                XCTAssertEqual(FolderAccessStatusCopy.hint(for: status), FolderAccessStatusCopy.hint)
            case .notAllowed:
                XCTAssertEqual(FolderAccessStatusCopy.action(status), .openPrivacySettings)
                XCTAssertNotEqual(FolderAccessStatusCopy.action(status), .askAgain)
                XCTAssertEqual(FolderAccessStatusCopy.detail(status), FolderAccessStatusCopy.notAllowedDetail)
                XCTAssertEqual(FolderAccessStatusCopy.hint(for: status), FolderAccessStatusCopy.hint)
            case .allowed:
                XCTAssertEqual(FolderAccessStatusCopy.action(status), .openPrivacySettings)
                XCTAssertNil(FolderAccessStatusCopy.hint(for: status))
            case .notNeeded, .unsupported:
                XCTAssertNil(FolderAccessStatusCopy.action(status))
                XCTAssertNil(FolderAccessStatusCopy.hint(for: status))
            }
            XCTAssertFalse(FolderAccessStatusCopy.line(status).contains("/"))
            XCTAssertFalse(FolderAccessStatusCopy.line(status).contains("~"))
        }
        XCTAssertEqual(FolderAccessStatusCopy.line(.notNeeded), "No permission needed")
        XCTAssertEqual(
            FolderAccessStatusCopy.line(.unsupported),
            "GridBack doesn't read wallpapers from here"
        )
        XCTAssertEqual(FolderAccessStatusCopy.buttonTitle(.allow), "Allow…")
        XCTAssertEqual(FolderAccessStatusCopy.buttonTitle(.askAgain), "Ask again")
        XCTAssertEqual(FolderAccessStatusCopy.buttonTitle(.openPrivacySettings), "Open Privacy Settings")
    }

    func testPlacePhrasesNameTheFolderKindOnly() {
        for place in WallpaperPathPlace.allCases {
            for volumeKind in FolderVolumeKind.allCases {
                let phrase = FolderAccessStatusCopy.placePhrase(place, volumeKind: volumeKind)
                XCTAssertFalse(phrase.contains("/"), phrase)
                XCTAssertFalse(phrase.contains("~"), phrase)
                XCTAssertFalse(phrase.contains("Users"), phrase)
            }
        }
        XCTAssertEqual(FolderAccessStatusCopy.placePhrase(.pictures, volumeKind: .none), "In your Pictures folder")
        XCTAssertEqual(FolderAccessStatusCopy.placePhrase(.photosLibrary, volumeKind: .none), "In your Photos library")
        XCTAssertEqual(FolderAccessStatusCopy.placePhrase(.volumes, volumeKind: .network), "On a network disk")
    }

    func testAllowingARefusedFolderDropsThePlainPictureAndOpensTheFile() {
        XCTAssertEqual(
            FolderPictureChoice.choose(decision: .tryRead, placeAllowsOpen: true),
            .openFile
        )
        XCTAssertEqual(
            FolderPictureChoice.choose(decision: .fallback, placeAllowsOpen: true),
            .plainFallback
        )
        XCTAssertEqual(
            FolderPictureChoice.choose(decision: .offerAsk, placeAllowsOpen: true),
            .plainFallback
        )
        XCTAssertEqual(
            FolderPictureChoice.choose(decision: .doNotTouch, placeAllowsOpen: true),
            .plainFallback
        )
        XCTAssertEqual(
            FolderPictureChoice.choose(decision: .tryRead, placeAllowsOpen: false),
            .plainFallback
        )

        let plainKey = WallpaperCacheIdentity.key(
            token: "protected",
            pixelWidth: 100,
            pixelHeight: 80,
            appearance: .dark,
            kind: .fallback,
            imageIndex: nil
        )
        let unreadKey = WallpaperCacheIdentity.key(
            token: "unreadable",
            pixelWidth: 100,
            pixelHeight: 80,
            appearance: .dark,
            kind: .unreadable,
            imageIndex: nil
        )
        let pictureKey = WallpaperCacheIdentity.key(
            token: "picture",
            pixelWidth: 100,
            pixelHeight: 80,
            appearance: .dark,
            kind: .still,
            imageIndex: 0
        )
        XCTAssertTrue(WallpaperPictureStore.shouldDropRefusedFallback(cacheKey: plainKey, accessAllowed: true))
        XCTAssertTrue(WallpaperPictureStore.shouldDropRefusedFallback(cacheKey: unreadKey, accessAllowed: true))
        XCTAssertFalse(WallpaperPictureStore.shouldDropRefusedFallback(cacheKey: plainKey, accessAllowed: false))
        XCTAssertFalse(WallpaperPictureStore.shouldDropRefusedFallback(cacheKey: pictureKey, accessAllowed: true))
        XCTAssertFalse(
            WallpaperPictureStore.shouldKeep(
                hasPicture: true,
                completedCacheKey: plainKey,
                currentCacheKey: pictureKey
            )
        )

        let before = FolderAccessStatus.make(
            place: .downloads,
            volumeKind: .none,
            asked: true,
            granted: false,
            denied: true,
            lastRead: .denied
        )
        let after = FolderAccessStatus.make(
            place: .downloads,
            volumeKind: .none,
            asked: true,
            granted: true,
            denied: false,
            lastRead: .granted
        )
        XCTAssertEqual(before, .notAllowed)
        XCTAssertEqual(after, .allowed)
        XCTAssertEqual(
            GrantedPictureFrame.resolve(classified: .plainBlur, imageCount: 0, accessGranted: true),
            .index(0)
        )
        XCTAssertEqual(
            GrantedPictureFrame.resolve(classified: .plainBlur, imageCount: 2, accessGranted: true),
            .plainBlur
        )
        XCTAssertEqual(
            GrantedPictureFrame.resolve(classified: .index(1), imageCount: 2, accessGranted: true),
            .index(1)
        )

        // The grid is already open and waiting on the new picture. The blur is shown
        // for this open, not held until the next one.
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: true,
                completedGeneration: 3,
                completedCacheKey: pictureKey,
                currentGeneration: 3,
                currentCacheKey: pictureKey,
                stillWanted: true
            ),
            .picture
        )
        XCTAssertEqual(
            WallpaperBackdropChoice.choose(
                hasPicture: false,
                completedGeneration: 3,
                completedCacheKey: plainKey,
                currentGeneration: 3,
                currentCacheKey: pictureKey,
                stillWanted: true
            ),
            .ignore
        )
    }

    func testPictureTargetUsesPathTextAndSkipsColourAndAerial() {
        let pictures = FolderAccessTarget.picture(
            provider: WallpaperStoreIndex.imageProvider,
            isFolder: false,
            storePaths: ["/Users/example/Pictures/wall.jpg"],
            workspacePath: nil
        )
        XCTAssertEqual(pictures?.place, .pictures)

        let photos = FolderAccessTarget.picture(
            provider: WallpaperStoreIndex.imageProvider,
            isFolder: false,
            storePaths: ["/Users/example/Pictures/Example.photoslibrary/wall.jpg"],
            workspacePath: nil
        )
        XCTAssertEqual(photos?.place, .photosLibrary)

        XCTAssertNil(
            FolderAccessTarget.picture(
                provider: WallpaperStoreIndex.colorProvider,
                isFolder: false,
                storePaths: ["/Users/example/Desktop/wall.jpg"],
                workspacePath: "/Users/example/Desktop/wall.jpg"
            )
        )
        XCTAssertNil(
            FolderAccessTarget.picture(
                provider: WallpaperStoreIndex.aerialsProvider,
                isFolder: false,
                storePaths: [],
                workspacePath: "/Users/example/Desktop/wall.jpg"
            )
        )

        let folder = FolderAccessTarget.picture(
            provider: WallpaperStoreIndex.imageFolderProvider,
            isFolder: true,
            storePaths: [],
            workspacePath: "/Users/example/Downloads/frame.jpg"
        )
        XCTAssertEqual(folder?.place, .downloads)
    }

    private func expectedStatus(
        place: WallpaperPathPlace,
        volumeKind: FolderVolumeKind,
        asked: Bool,
        granted: Bool,
        denied: Bool,
        lastRead: FolderReadResult
    ) -> FolderAccessStatus {
        if place == .photosLibrary || (place == .volumes && volumeKind == .network) {
            return .unsupported
        }
        if place == .pictures || place == .system || place == .other || place == .icloud
            || (place == .volumes && volumeKind == .fixed) {
            return .notNeeded
        }
        if denied || lastRead == .denied {
            return .notAllowed
        }
        if granted || lastRead == .granted {
            return .allowed
        }
        if asked {
            return .notNow
        }
        return .notAsked
    }
}
