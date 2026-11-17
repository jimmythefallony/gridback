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

    func testEditChordsAreIgnoredWithSearchActiveAndInactive() {
        let chords: [(String, UInt16, KeyModifiers, String)] = [
            ("Cmd-A", 0, .command, "a"),
            ("Cmd-C", 8, .command, "c"),
            ("Cmd-V", 9, .command, "v"),
            ("Cmd-X", 7, .command, "x"),
            ("Cmd-Z", 6, .command, "z"),
            ("Shift-Cmd-Z", 6, [.command, .shift], "z"),
        ]
        for (name, keyCode, modifiers, characters) in chords {
            for searching in [true, false] {
                XCTAssertEqual(
                    SearchKeyRouting.action(
                        keyCode: keyCode,
                        characters: characters,
                        modifiers: modifiers,
                        isSearching: searching,
                        columns: 7
                    ),
                    .ignored,
                    name
                )
                var drag = HeldDrag()
                XCTAssertEqual(
                    OverlayCommanding.command(
                        keyCode: keyCode,
                        characters: characters,
                        modifiers: modifiers,
                        isSearching: searching,
                        folderIsOpen: false,
                        columns: 7,
                        drag: &drag
                    ),
                    .key(.ignored),
                    name
                )
                XCTAssertFalse(drag.isActive)
            }
        }
    }

    func testCommandUndoDoesNotCancelADrag() {
        var drag = HeldDrag()
        drag.beginGrid(appID: "notes", origin: Layout(pages: [["notes"]], metrics: GridMetrics(columns: 7, rows: 1)))
        let command = OverlayCommanding.command(
            keyCode: 6,
            characters: "z",
            modifiers: .command,
            isSearching: false,
            folderIsOpen: false,
            columns: 7,
            drag: &drag
        )
        XCTAssertEqual(command, .key(.ignored))
        XCTAssertTrue(drag.isActive)
    }

    func testFunctionKeyGlyphsAreNotSearchText() {
        XCTAssertNil(SearchKeyRouting.searchableText(from: "\u{F700}"))
        XCTAssertEqual(SearchKeyRouting.searchableText(from: "é"), "é")
    }
}

final class SearchQueryTextTests: XCTestCase {
    func testNewlinesAndTabsBecomeSpaces() {
        XCTAssertEqual(SearchQueryText.cleaned("Notes\nMail"), "Notes Mail")
        XCTAssertEqual(SearchQueryText.cleaned("Notes\rMail"), "Notes Mail")
        XCTAssertEqual(SearchQueryText.cleaned("Notes\r\nMail"), "Notes Mail")
        XCTAssertEqual(SearchQueryText.cleaned("Notes\tMail"), "Notes Mail")
        XCTAssertEqual(SearchQueryText.cleaned("a\r\nb\tc"), "a b c")
        XCTAssertEqual(SearchQueryText.cleaned(SearchQueryText.cleaned("a\r\nb\t")), "a b ")
    }

    func testPlainTextAndEmptyTextStayAsTheyAre() {
        XCTAssertEqual(SearchQueryText.cleaned(""), "")
        XCTAssertEqual(SearchQueryText.cleaned("Café Notes"), "Café Notes")
    }

    func testQueryIsCappedAtAboutOneHundredCharacters() {
        XCTAssertEqual(SearchQueryText.limit, 100)
        let exact = String(repeating: "n", count: SearchQueryText.limit)
        XCTAssertEqual(SearchQueryText.cleaned(exact), exact)
        XCTAssertEqual(SearchQueryText.cleaned(exact + "x"), exact)
        let almost = String(repeating: "a", count: 99)
        XCTAssertEqual(SearchQueryText.cleaned(almost + "\n" + "b"), almost + " ")
    }
}
