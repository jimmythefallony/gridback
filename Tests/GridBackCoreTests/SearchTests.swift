import XCTest
import GridBackCore

final class SearchMatcherTests: XCTestCase {
    private let apps = [
        AppRecord(bundleIdentifier: "notes", bundlePath: "/Applications/Notes.app", displayName: "Notes"),
        AppRecord(bundleIdentifier: "notion", bundlePath: "/Applications/Notion.app", displayName: "Notion"),
        AppRecord(bundleIdentifier: "mail", bundlePath: "/Applications/Mail.app", displayName: "Mail"),
        AppRecord(bundleIdentifier: "gmail", bundlePath: "/Applications/Gmail.app", displayName: "Gmail"),
        AppRecord(bundleIdentifier: "cafe", bundlePath: "/Applications/Cafe.app", displayName: "Café Notes"),
        AppRecord(bundleIdentifier: "store", bundlePath: "/Applications/App Store.app", displayName: "App Store")
    ]

    func testBlankQueryMatchesNothing() {
        XCTAssertTrue(SearchMatcher.filter(apps, query: "   ").isEmpty)
    }

    func testPrefixOutranksSubstringAndKeepsOriginalOrderInsideARank() {
        let result = SearchMatcher.filter(apps, query: "not").map(\.id)
        XCTAssertEqual(result, ["notes", "notion", "cafe"])
    }

    func testCaseAndDiacriticsAreIgnored() {
        XCTAssertEqual(SearchMatcher.filter(apps, query: "cafe").map(\.id), ["cafe"])
        XCTAssertEqual(SearchMatcher.filter(apps, query: "MAIL").map(\.id), ["mail", "gmail"])
    }

    func testWordsMatchOutOfOrderWhenTheyAreNotASubstring() {
        let result = SearchMatcher.filter(apps, query: "store app").map(\.id)
        XCTAssertEqual(result, ["store"])
    }

    func testNoMatchIsEmpty() {
        XCTAssertTrue(SearchMatcher.filter(apps, query: "photoshop").isEmpty)
    }
}

final class SearchKeyRoutingTests: XCTestCase {
    func testEscapeClearsSearchBeforeDismissing() {
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 53, characters: "", modifiers: [], isSearching: true, columns: 7),
            .clearSearch
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 53, characters: "", modifiers: [], isSearching: false, columns: 7),
            .dismiss
        )
    }

    func testTypingStartsSearchAndReturnLaunchesOnlyWhileSearching() {
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 15, characters: "r", modifiers: [], isSearching: false, columns: 7),
            .startOrAppend("r")
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 36, characters: "\r", modifiers: [], isSearching: true, columns: 7),
            .launchSelected
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 36, characters: "\r", modifiers: [], isSearching: false, columns: 7),
            .ignored
        )
    }

    func testBackspaceAndArrowsDependOnSearch() {
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 51, characters: "", modifiers: [], isSearching: true, columns: 7),
            .backspace
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 123, characters: "", modifiers: [], isSearching: false, columns: 7),
            .changePage(delta: -1)
        )
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 125, characters: "", modifiers: [], isSearching: true, columns: 7),
            .moveSelection(delta: 7)
        )
    }

    func testCommandShortcutsAreNotTypedIntoSearch() {
        XCTAssertEqual(
            SearchKeyRouting.action(keyCode: 15, characters: "r", modifiers: .command, isSearching: true, columns: 7),
            .ignored
        )
    }

    func testFunctionKeyGlyphsAreNotSearchText() {
        XCTAssertNil(SearchKeyRouting.searchableText(from: "\u{F700}"))
        XCTAssertEqual(SearchKeyRouting.searchableText(from: "é"), "é")
    }
}
