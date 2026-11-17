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

    func testNeutralFillChoosesInkFromLuminanceAndPicturesStayLight() {
        let pale = WallpaperNeutralFill.color(for: .light)
        let charcoal = WallpaperNeutralFill.color(for: .dark)
        XCTAssertGreaterThanOrEqual(InkContrast.relativeLuminance(pale), InkContrast.darkInkLuminance)
        XCTAssertLessThanOrEqual(InkContrast.relativeLuminance(charcoal), InkContrast.lightInkLuminance)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(pale), previous: .light), .dark)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(pale), previous: .dark), .dark)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(charcoal), previous: .light), .light)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(charcoal), previous: .dark), .light)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(pale), previous: .dark).windowAppearance, .aqua)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(charcoal), previous: .dark).windowAppearance, .darkAqua)
        XCTAssertEqual(Ink.forBackdrop(.picture, previous: .dark), .light)
        XCTAssertEqual(Ink.forBackdrop(.picture, previous: .light), .light)
        XCTAssertEqual(Ink.forBackdrop(.solidColor, previous: .dark), .light)
        XCTAssertEqual(BackdropInkSource.resolve(hasPicture: true, isSolidColor: true, fill: pale), .picture)
        XCTAssertEqual(BackdropInkSource.resolve(hasPicture: false, isSolidColor: true, fill: pale), .solidColor)
        XCTAssertEqual(BackdropInkSource.resolve(hasPicture: false, isSolidColor: false, fill: pale), .neutralFill(pale))
    }

    func testLuminanceChoiceKeepsThePreviousInkInsideTheGap() {
        XCTAssertLessThan(InkContrast.lightInkLuminance, InkContrast.darkInkLuminance)
        let low = InkContrast.lightInkLuminance
        let high = InkContrast.darkInkLuminance
        XCTAssertEqual(Ink.forLuminance(high, previous: .light), .dark)
        XCTAssertEqual(Ink.forLuminance(high - 0.001, previous: .light), .light)
        XCTAssertEqual(Ink.forLuminance(high - 0.001, previous: .dark), .dark)
        XCTAssertEqual(Ink.forLuminance(low, previous: .dark), .light)
        XCTAssertEqual(Ink.forLuminance(low + 0.001, previous: .dark), .dark)
        XCTAssertEqual(Ink.forLuminance(low + 0.001, previous: .light), .light)

        let between = (low + high) / 2
        var ink = Ink.light
        ink = Ink.forLuminance(between, previous: ink)
        XCTAssertEqual(ink, .light)
        ink = Ink.forLuminance(high, previous: ink)
        XCTAssertEqual(ink, .dark)
        ink = Ink.forLuminance(between, previous: ink)
        XCTAssertEqual(ink, .dark)
        ink = Ink.forLuminance(low, previous: ink)
        XCTAssertEqual(ink, .light)

        let mid = WallpaperSolidColor(red: 0.5, green: 0.5, blue: 0.5)
        let midLuminance = InkContrast.relativeLuminance(mid)
        XCTAssertGreaterThan(midLuminance, InkContrast.lightInkLuminance)
        XCTAssertLessThan(midLuminance, InkContrast.darkInkLuminance)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(mid), previous: .light), .light)
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(mid), previous: .dark), .dark)
    }

    func testFallbackInkMeetsContrastOnTheFillAndUnderTheVeil() {
        XCTAssertEqual(InkContrast.relativeLuminance(red: 0, green: 0, blue: 0), 0, accuracy: 0.000_000_1)
        XCTAssertEqual(InkContrast.relativeLuminance(red: 1, green: 1, blue: 1), 1, accuracy: 0.000_000_1)
        XCTAssertEqual(InkContrast.contrastRatio(1, against: 0), 21, accuracy: 0.000_000_1)
        let half = InkContrast.composite(.white(opacity: 0.5), over: WallpaperSolidColor(red: 0, green: 0, blue: 0))
        XCTAssertEqual(half.red, 0.5, accuracy: 0.000_000_1)
        XCTAssertEqual(half.green, 0.5, accuracy: 0.000_000_1)
        XCTAssertEqual(half.blue, 0.5, accuracy: 0.000_000_1)

        assertReadable(Ink.dark, on: WallpaperNeutralFill.color(for: .light))
        assertReadable(Ink.light, on: WallpaperNeutralFill.color(for: .dark))
    }

    func testInkCrossfadeLastsAQuarterSecond() {
        XCTAssertEqual(InkCrossfade.duration, 0.25, accuracy: 0.000_000_1)
    }

    private func assertReadable(_ ink: Ink, on fill: WallpaperSolidColor, file: StaticString = #filePath, line: UInt = #line) {
        let keep = 1 - WallpaperDim.black
        let veiled = WallpaperSolidColor(red: fill.red * keep, green: fill.green * keep, blue: fill.blue * keep)
        for surface in [fill, veiled] {
            let label = InkContrast.contrastRatio(
                InkContrast.relativeLuminance(ink.label),
                against: InkContrast.relativeLuminance(surface)
            )
            XCTAssertGreaterThanOrEqual(label, InkContrast.textMinimum, file: file, line: line)
            let quiet = InkContrast.composite(ink.quiet, over: surface)
            let quietRatio = InkContrast.contrastRatio(
                InkContrast.relativeLuminance(quiet),
                against: InkContrast.relativeLuminance(surface)
            )
            XCTAssertGreaterThanOrEqual(quietRatio, InkContrast.textMinimum, file: file, line: line)
            let parts = [
                ink.searchPlaceholder,
                ink.pageDot(distance: 0),
                ink.pageArrow(enabled: true),
                ink.dropRing
            ]
            for part in parts {
                let drawn = InkContrast.composite(part, over: surface)
                let ratio = InkContrast.contrastRatio(
                    InkContrast.relativeLuminance(drawn),
                    against: InkContrast.relativeLuminance(surface)
                )
                XCTAssertGreaterThanOrEqual(ratio, InkContrast.graphicMinimum, file: file, line: line)
            }
        }
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
