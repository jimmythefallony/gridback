import XCTest
import GridBackCore

final class CatalogRulesTests: XCTestCase {
    func testIncludesTopLevelAndUtilityApps() {
        XCTAssertTrue(CatalogPathRules.shouldIncludeApp(path: "/Applications/Safari.app"))
        XCTAssertTrue(CatalogPathRules.shouldIncludeApp(path: "/Applications/Utilities/Terminal.app"))
        XCTAssertTrue(CatalogPathRules.shouldIncludeApp(path: "/System/Applications/Apps.app"))
    }

    func testExcludesHelpersNestedInsideAnotherApp() {
        let helper = "/Applications/Firefox.app/Contents/MacOS/plugin-container.app"
        XCTAssertFalse(CatalogPathRules.shouldIncludeApp(path: helper))
        XCTAssertTrue(CatalogPathRules.isInsideAnotherApp(helper))
    }

    func testDoesNotDescendIntoAppBundlesOrHiddenPackages() {
        XCTAssertFalse(CatalogPathRules.shouldDescend(name: "Safari.app", depth: 0))
        XCTAssertFalse(CatalogPathRules.shouldDescend(name: ".hidden", depth: 0))
        XCTAssertFalse(CatalogPathRules.shouldDescend(name: "Thing.framework", depth: 0))
        XCTAssertFalse(CatalogPathRules.shouldDescend(name: "Widget.plugin", depth: 1))
        XCTAssertTrue(CatalogPathRules.shouldDescend(name: "Utilities", depth: 0))
        XCTAssertFalse(CatalogPathRules.shouldDescend(name: "Deeper", depth: CatalogPathRules.maxScanDepth))
    }

    func testHiddenAppNamesAreExcluded() {
        XCTAssertFalse(CatalogPathRules.shouldIncludeApp(path: "/Applications/.Secret.app"))
    }

    func testDisplayNamePreferenceAndBackgroundOnly() {
        let record = BundleInfoParser.makeRecord(
            infoDictionary: [
                "CFBundleIdentifier": "com.example.notes",
                "CFBundleDisplayName": "Notes",
                "CFBundleName": "NotesRaw"
            ],
            localizedDisplayName: "Notes Local",
            localizedBundleName: "Ignored",
            bundlePath: "/Applications/Notes.app"
        )
        XCTAssertEqual(record?.displayName, "Notes Local")
        XCTAssertEqual(record?.id, "com.example.notes")

        let fromFileName = BundleInfoParser.makeRecord(
            infoDictionary: [:],
            localizedDisplayName: nil,
            localizedBundleName: "  ",
            bundlePath: "/Applications/Plain.app"
        )
        XCTAssertEqual(fromFileName?.displayName, "Plain")
        XCTAssertEqual(fromFileName?.id, "/Applications/Plain.app")

        let background = BundleInfoParser.makeRecord(
            infoDictionary: [
                "CFBundleIdentifier": "com.example.agent",
                "CFBundleName": "Agent",
                "LSBackgroundOnly": true
            ],
            localizedDisplayName: nil,
            localizedBundleName: nil,
            bundlePath: "/Applications/Agent.app"
        )
        XCTAssertNil(background)

        XCTAssertTrue(BundleInfoParser.isBackgroundOnly(["LSBackgroundOnly": "YES"]))
        XCTAssertFalse(BundleInfoParser.isBackgroundOnly(["LSUIElement": true]))
    }
}
