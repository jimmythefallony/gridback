import XCTest
@testable import GridBackCore

final class WallpaperDiagnosticsTests: XCTestCase {
    func testRedactionHidesSlashesAndLongStrings() {
        XCTAssertEqual(WallpaperDiagnosticText.reveal("Golden Gate"), "Golden Gate")
        XCTAssertEqual(WallpaperDiagnosticText.reveal("night-city"), "night-city")
        XCTAssertEqual(WallpaperDiagnosticText.reveal("Dusty Rose"), "Dusty Rose")
        XCTAssertEqual(WallpaperDiagnosticText.reveal("Tahoe"), "Tahoe")
        let kept = String(repeating: "a", count: 63)
        XCTAssertEqual(WallpaperDiagnosticText.reveal(kept), kept)
        XCTAssertNil(WallpaperDiagnosticText.reveal(String(repeating: "a", count: 64)))
        XCTAssertNil(WallpaperDiagnosticText.reveal("folder/name"))
        XCTAssertNil(WallpaperDiagnosticText.reveal("/Library/Desktop Pictures/Tahoe.heic"))
        XCTAssertNil(WallpaperDiagnosticText.reveal("~/Desktop/wall.jpg"))
        XCTAssertNil(WallpaperDiagnosticText.reveal("jimmy", secrets: ["jimmy"]))
        XCTAssertEqual(WallpaperDiagnosticText.reveal("Dusty Rose", secrets: ["rose"]), "Dusty Rose")
        let display = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        XCTAssertNil(WallpaperDiagnosticText.reveal("id \(display) end", secrets: [display]))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Users/example/Desktop/a.heic"))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Users/example/Documents/a.heic"))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Users/example/Downloads/a.heic"))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Users/example/Library/Mobile Documents/a.heic"))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Users/example/Pictures/Lib.photoslibrary/a.heic"))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Volumes/Extra/a.heic"))
        XCTAssertFalse(WallpaperDiagnostics.allowsFileAccess(to: "/Library/Example/../../Users/example/Desktop/a.heic"))
        XCTAssertTrue(WallpaperDiagnostics.allowsFileAccess(to: WallpaperDiagnostics.entriesJSONPath))

        let lines = WallpaperDiagnostics.lines(
            store: nil,
            displayUUID: nil,
            legacyFileName: "/Users/example/Desktop/wall.jpg",
            probe: .closed
        )
        XCTAssertEqual(lines.first, "wallpaper-diag provider=none")
        XCTAssertTrue(lines.contains("wallpaper-diag legacy=omitted"))
        XCTAssertTrue(lines.contains("wallpaper-diag asset=none"))
        XCTAssertTrue(lines.contains("wallpaper-diag heic=none"))
        let text = lines.joined(separator: "\n")
        XCTAssertFalse(text.contains("/"))
        XCTAssertFalse(text.contains("example"))
    }

    func testDataKindDetectsPlistArchiverJSONAndOther() {
        let plain = try! PropertyListSerialization.data(fromPropertyList: ["type": "still"], format: .binary, options: 0)
        XCTAssertTrue(plain.starts(with: Data("bplist00".utf8)))
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(plain), .bplist00)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(plain).rawValue, "bplist00")

        let archived = try! PropertyListSerialization.data(
            fromPropertyList: ["$archiver": "NSKeyedArchiver"],
            format: .binary,
            options: 0
        )
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(archived), .archiver)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(archived).rawValue, "contains $archiver")
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(Data("bplist00$archiver".utf8)), .archiver)

        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(Data("{\"type\":\"gradient\"}".utf8)), .json)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(Data("\n[1, 2]".utf8)), .json)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(Data("{\"type\":\"gradient\"}".utf8)).rawValue, "JSON")
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(Data("hello".utf8)), .other)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(Data()), .other)
        let xml = try! PropertyListSerialization.data(fromPropertyList: ["type": "still"], format: .xml, options: 0)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(xml), .other)
        XCTAssertEqual(WallpaperDiagnosticDataKind.detect(xml).rawValue, "other")
    }

    func testAColourChoiceDoesNotOpenTheAssetCatalogOrAProtectedFile() {
        var calls: [String] = []
        let probe = WallpaperDiagnosticProbe(
            status: { path in
                calls.append(path)
                return WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: true)
            },
            read: { path in
                calls.append(path)
                return nil
            },
            heic: { path in
                calls.append(path)
                return nil
            },
            unarchive: { _ in
                XCTFail("A colour value was unarchived")
                return nil
            }
        )
        let note = String(repeating: "q", count: 64)
        let store: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Desktop": [
                    "Content": [
                        "Choices": [[
                            "Provider": WallpaperStoreIndex.colorProvider,
                            "Configuration": [
                                "systemColor": "Dusty Rose",
                                "type": "gradient",
                                "note": note,
                                "blocked": "/Users/example/Desktop/wall.heic"
                            ]
                        ] as [String: Any]]
                    ]
                ]
            ]
        ]
        let lines = WallpaperDiagnostics.lines(
            store: store,
            displayUUID: nil,
            legacyFileName: "DefaultDesktop.heic",
            secrets: ["example"],
            probe: probe
        )
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(lines.contains("wallpaper-diag provider=\(WallpaperStoreIndex.colorProvider)"))
        XCTAssertTrue(lines.contains { $0.contains("systemColor=String(Dusty Rose)") })
        XCTAssertTrue(lines.contains { $0.contains("type=String(gradient)") })
        XCTAssertTrue(lines.contains("wallpaper-diag asset=none"))
        XCTAssertTrue(lines.contains("wallpaper-diag encoded=none"))
        XCTAssertTrue(lines.contains("wallpaper-diag heic skipped=protected place=desktop"))
        XCTAssertTrue(lines.contains("wallpaper-diag legacy=DefaultDesktop.heic"))
        let text = lines.joined(separator: "\n")
        XCTAssertFalse(text.contains(note))
        XCTAssertFalse(text.contains("/"))
        XCTAssertFalse(text.contains("example"))
        XCTAssertFalse(text.contains("wall.heic"))
    }

    func testReportHidesPathsAndReadsOnlySafeFiles() {
        let display = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let long = String(repeating: "n", count: 64)
        let encoded = try! PropertyListSerialization.data(
            fromPropertyList: ["$archiver": "NSKeyedArchiver", "color": "Dusty Rose"],
            format: .binary,
            options: 0
        )
        let desktopPlist = try! PropertyListSerialization.data(
            fromPropertyList: [
                "appearance": "dark",
                "image": "/Users/example/Pictures/Sequoia.heic"
            ],
            format: .xml,
            options: 0
        )
        let heicPath = "/Library/Desktop Pictures/Hidden.heic"
        let madePath = "/Library/Application Support/com.apple.wallpaper/Pack.madesktop"
        let catalog = Data("""
        {"assets":[{"id":"night-city","previewImage":"preview.jpg","video":"shots/clip.mov","blocked":"/Users/example/Desktop/secret.jpg"}]}
        """.utf8)
        let preview = WallpaperDiagnostics.customerDirectory + "/preview.jpg"
        let movie = WallpaperDiagnostics.customerDirectory + "/shots/clip.mov"
        var seen: [String] = []
        let probe = WallpaperDiagnosticProbe(
            status: { path in
                seen.append("status \(path)")
                let known = [
                    WallpaperDiagnostics.entriesJSONPath,
                    preview,
                    movie,
                    heicPath,
                    madePath
                ]
                guard known.contains(path) else {
                    XCTFail("Unexpected file check \(path)")
                    return WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: true)
                }
                return WallpaperDiagnosticFileStatus(exists: true, readable: true, refused: false)
            },
            read: { path in
                seen.append("read \(path)")
                if path == WallpaperDiagnostics.entriesJSONPath { return catalog }
                if path == madePath { return desktopPlist }
                XCTFail("Unexpected read \(path)")
                return nil
            },
            heic: { path in
                seen.append("heic \(path)")
                XCTAssertEqual(path, heicPath)
                return WallpaperDiagnosticHEIC(h24: true, solar: false, apr: true, frames: 8)
            },
            unarchive: { data in
                seen.append("unarchive \(data.count)")
                XCTAssertEqual(data, encoded)
                return WallpaperDiagnosticArchive(classNames: ["NSColor"], components: [0.2, 0.3, 0.4, 1])
            }
        )
        let store: [String: Any] = [
            "Displays": [
                display: [
                    "Desktop": [
                        "Content": [
                            "Choices": [[
                                "Provider": WallpaperStoreIndex.aerialsProvider,
                                "Configuration": [
                                    "assetID": "night-city",
                                    "type": "aerial",
                                    "url": "file:///Library/Desktop Pictures/Hidden.heic",
                                    "note": long,
                                    "pack": madePath,
                                    "swatch": ["components": [0.1, 0.2, 0.3]],
                                    "blocked": [
                                        "/Users/example/Desktop/secret.heic",
                                        "/Users/example/Documents/secret.heic",
                                        "/Users/example/Downloads/secret.heic",
                                        "/Users/example/Library/Mobile Documents/secret.heic",
                                        "/Users/example/Pictures/Lib.photoslibrary/secret.heic",
                                        "/Volumes/Extra/secret.heic",
                                        "/Users/example/Desktop/custom.madesktop"
                                    ]
                                ],
                                "Files": [
                                    ["relative": heicPath],
                                    "clip.mov"
                                ],
                                "EncodedOptionValues": encoded
                            ] as [String: Any]],
                            "Shuffle": false
                        ]
                    ]
                ]
            ]
        ]
        let lines = WallpaperDiagnostics.lines(
            store: store,
            displayUUID: display.lowercased(),
            legacyFileName: "DefaultDesktop.heic",
            secrets: [display, "example"],
            probe: probe
        )
        XCTAssertTrue(lines.contains("wallpaper-diag provider=\(WallpaperStoreIndex.aerialsProvider)"))
        XCTAssertTrue(lines.contains("wallpaper-diag entryKeys=Desktop"))
        XCTAssertTrue(lines.contains("wallpaper-diag files count=2 extensions=heic,mov"))
        XCTAssertTrue(lines.contains("wallpaper-diag legacy=DefaultDesktop.heic"))
        XCTAssertTrue(lines.contains("wallpaper-diag content=Dict(Choices=Array(Dict),Shuffle=Bool(false))"))
        XCTAssertTrue(lines.contains { $0.contains("assetID=String(night-city)") })
        XCTAssertTrue(lines.contains { $0.contains("type=String(aerial)") })
        XCTAssertTrue(lines.contains { $0.contains("url=String)") })
        XCTAssertTrue(lines.contains { $0.contains("note=String,") })
        XCTAssertTrue(lines.contains { $0.contains("components=[0.1000,0.2000,0.3000]") })
        XCTAssertTrue(lines.contains("wallpaper-diag encoded bytes=\(encoded.count) kind=contains $archiver"))
        XCTAssertTrue(lines.contains { $0.contains("color=String(Dusty Rose)") })
        XCTAssertTrue(lines.contains("wallpaper-diag encoded classes=NSColor components=0.2000,0.3000,0.4000,1.0000"))
        XCTAssertTrue(lines.contains(
            "wallpaper-diag asset id=night-city entriesExists=true entriesReadable=true containsID=true snapshotReadable=true movReadable=true"
        ))
        XCTAssertTrue(lines.contains { $0.contains("id=String(night-city)") && $0.contains("previewImage=String(preview.jpg)") })
        XCTAssertTrue(lines.contains { $0.contains("appearance=String(dark)") && $0.contains("image=String") })
        XCTAssertTrue(lines.contains("wallpaper-diag heic h24=true solar=false apr=true frames=8"))
        for place in ["desktop", "documents", "downloads", "icloud", "photosLibrary", "volumes"] {
            XCTAssertTrue(lines.contains("wallpaper-diag heic skipped=protected place=\(place)"))
        }
        XCTAssertTrue(lines.contains("wallpaper-diag madesktop skipped=protected place=desktop"))
        let text = lines.joined(separator: "\n")
        XCTAssertFalse(text.contains("/"))
        XCTAssertFalse(text.contains(display))
        XCTAssertFalse(text.contains("example"))
        XCTAssertFalse(text.contains(long))
        XCTAssertFalse(text.contains("Hidden"))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(seen.contains { $0.contains("/Users") || $0.contains("/Volumes") || $0.contains("photoslibrary") })
        XCTAssertTrue(seen.contains("read \(WallpaperDiagnostics.entriesJSONPath)"))
        XCTAssertTrue(seen.contains("heic \(heicPath)"))
        XCTAssertTrue(seen.contains("read \(madePath)"))
        XCTAssertTrue(seen.contains("status \(preview)"))
        XCTAssertTrue(seen.contains("status \(movie)"))
        XCTAssertEqual(seen.filter { $0.hasPrefix("unarchive") }.count, 1)
    }
}
