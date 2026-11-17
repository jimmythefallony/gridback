import XCTest
import GridBackCore

final class InkTests: XCTestCase {
    func testLightInkMatchesTheCurrentWhiteOnDarkColours() {
        let ink = Ink.light

        XCTAssertEqual(ink.label, .white(opacity: 1))
        XCTAssertEqual(ink.label.red, 1)
        XCTAssertEqual(ink.label.green, 1)
        XCTAssertEqual(ink.label.blue, 1)
        XCTAssertEqual(ink.labelShadow, InkShadow(color: .black(opacity: 0.45), radius: 2, y: 1))
        XCTAssertEqual(ink.folderTitleShadow, InkShadow(color: .black(opacity: 0.35), radius: 2, y: 1))
        XCTAssertEqual(ink.quiet, .white(opacity: 0.85))
        XCTAssertEqual(ink.muted, .white(opacity: 0.65))
        XCTAssertEqual(ink.hoverHighlight, .white(opacity: 0.16))
        XCTAssertEqual(ink.selectionHighlight, .white(opacity: 0.28))
        XCTAssertEqual(ink.iconHighlight(selected: false, hovering: false), .white(opacity: 0))
        XCTAssertEqual(ink.iconHighlight(selected: false, hovering: true), .white(opacity: 0.16))
        XCTAssertEqual(ink.iconHighlight(selected: true, hovering: false), .white(opacity: 0.28))
        XCTAssertEqual(ink.iconHighlight(selected: true, hovering: true), .white(opacity: 0.28))
        XCTAssertEqual(ink.dropRing, .white(opacity: 0.9))
        XCTAssertEqual(ink.folderFill(armed: false), .white(opacity: 0.16))
        XCTAssertEqual(ink.folderFill(armed: true), .white(opacity: 0.28))
        XCTAssertEqual(ink.folderStroke(armed: false), .white(opacity: 0.28))
        XCTAssertEqual(ink.folderStroke(armed: true), .white(opacity: 0.95))
        XCTAssertEqual(ink.searchPill, .white(opacity: 0.16))
        XCTAssertEqual(ink.searchText, .white(opacity: 1))
        XCTAssertEqual(ink.searchPlaceholder, .white(opacity: 0.65))
        XCTAssertEqual(ink.searchCaret, .white(opacity: 1))
        XCTAssertEqual(ink.pageArrow(enabled: true), .white(opacity: 0.9))
        XCTAssertEqual(ink.pageArrow(enabled: false), .white(opacity: 0.28))
        XCTAssertEqual(ink.pageDot(distance: 0), .white(opacity: 0.95))
        XCTAssertEqual(ink.pageDot(distance: 1).opacity, 0.95 - 0.62, accuracy: 0.000_000_1)
        XCTAssertEqual(ink.pageDot(distance: 1).red, 1)
        XCTAssertEqual(ink.folderPanelFill, .white(opacity: 0.24))
        XCTAssertEqual(ink.folderPanelStroke, .white(opacity: 0.45))
        XCTAssertEqual(ink.windowAppearance, .darkAqua)
    }

    func testDarkInkUsesNearBlackLabelsAndNoTextShadow() {
        let ink = Ink.dark
        XCTAssertEqual(ink.label.red, Double(0x1D) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(ink.label.green, Double(0x1D) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(ink.label.blue, Double(0x1F) / 255, accuracy: 0.000_000_1)
        XCTAssertEqual(ink.label.opacity, 1)
        XCTAssertNil(ink.labelShadow)
        XCTAssertNil(ink.folderTitleShadow)
        XCTAssertEqual(ink.searchText.red, ink.label.red)
        XCTAssertEqual(ink.searchText.green, ink.label.green)
        XCTAssertEqual(ink.searchText.blue, ink.label.blue)
        XCTAssertEqual(ink.searchCaret, ink.label)
        XCTAssertEqual(ink.searchPlaceholder.opacity, 0.65)
        XCTAssertEqual(ink.windowAppearance, .aqua)
    }

    func testDarkInkHighlightsAreTheSameStrengthButDarker() {
        let dark = Ink.dark
        let light = Ink.light
        let pairs: [(InkColor, InkColor)] = [
            (dark.hoverHighlight, light.hoverHighlight),
            (dark.selectionHighlight, light.selectionHighlight),
            (dark.iconHighlight(selected: false, hovering: true), light.iconHighlight(selected: false, hovering: true)),
            (dark.iconHighlight(selected: true, hovering: false), light.iconHighlight(selected: true, hovering: false)),
            (dark.dropRing, light.dropRing),
            (dark.folderFill(armed: false), light.folderFill(armed: false)),
            (dark.folderFill(armed: true), light.folderFill(armed: true)),
            (dark.folderStroke(armed: true), light.folderStroke(armed: true)),
            (dark.searchPill, light.searchPill),
            (dark.pageDot(distance: 0), light.pageDot(distance: 0)),
            (dark.pageArrow(enabled: true), light.pageArrow(enabled: true)),
            (dark.pageArrow(enabled: false), light.pageArrow(enabled: false))
        ]
        for (darkColor, lightColor) in pairs {
            XCTAssertEqual(darkColor.opacity, lightColor.opacity)
            XCTAssertEqual(darkColor.red, dark.label.red)
            XCTAssertEqual(darkColor.green, dark.label.green)
            XCTAssertEqual(darkColor.blue, dark.label.blue)
            XCTAssertLessThan(darkColor.red, lightColor.red)
        }
    }
}
