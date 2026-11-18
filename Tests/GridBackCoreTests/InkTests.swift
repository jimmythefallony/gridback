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
        XCTAssertEqual(ink.searchPill, .black(opacity: Ink.lightSearchScrim))
        XCTAssertEqual(ink.searchText, .white(opacity: 1))
        XCTAssertEqual(ink.searchPlaceholder, .white(opacity: 0.65))
        XCTAssertEqual(ink.searchCaret, .white(opacity: 1))
        XCTAssertEqual(ink.pageArrow(enabled: true), .white(opacity: 0.9))
        XCTAssertEqual(ink.pageArrow(enabled: false), .white(opacity: 0.28))
        XCTAssertEqual(ink.pageDot(distance: 0), .white(opacity: Ink.pageDotCurrentOpacity))
        XCTAssertEqual(ink.pageDot(distance: 1).opacity, Ink.pageDotInactiveOpacity, accuracy: 0.000_000_1)
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
        XCTAssertEqual(ink.muted.opacity, Ink.darkMutedOpacity)
        XCTAssertEqual(ink.searchPlaceholder.opacity, Ink.darkMutedOpacity)
        XCTAssertEqual(ink.searchPill, .white(opacity: Ink.darkSearchScrim))
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
        XCTAssertEqual(Ink.forBackdrop(.solidColor(charcoal), previous: .dark), .light)
        XCTAssertEqual(Ink.forBackdrop(.solidColor(pale), previous: .light), .dark)
        XCTAssertEqual(BackdropInkSource.resolve(hasPicture: true, isSolidColor: true, fill: pale), .picture)
        XCTAssertEqual(BackdropInkSource.resolve(hasPicture: false, isSolidColor: true, fill: pale), .solidColor(pale))
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
        XCTAssertEqual(Ink.forBackdrop(.neutralFill(mid), previous: .dark), .light)
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

    func testShownColourIsTheFillTimesTheOpenVeil() {
        let fill = WallpaperSolidColor(red: 0.2, green: 0.4, blue: 0.8)
        let shown = InkContrast.shown(fill, veil: 0.25)
        XCTAssertEqual(shown.red, 0.2 * 0.75, accuracy: 0.000_000_1)
        XCTAssertEqual(shown.green, 0.4 * 0.75, accuracy: 0.000_000_1)
        XCTAssertEqual(shown.blue, 0.8 * 0.75, accuracy: 0.000_000_1)
        let normal = InkContrast.shown(fill)
        XCTAssertEqual(normal.red, fill.red * (1 - WallpaperDim.black), accuracy: 0.000_000_1)
        XCTAssertEqual(normal.green, fill.green * (1 - WallpaperDim.black), accuracy: 0.000_000_1)
        XCTAssertEqual(normal.blue, fill.blue * (1 - WallpaperDim.black), accuracy: 0.000_000_1)
        let open = InkContrast.shown(fill, veil: 0)
        XCTAssertEqual(open.red, fill.red, accuracy: 0.000_000_1)
        XCTAssertEqual(open.green, fill.green, accuracy: 0.000_000_1)
        XCTAssertEqual(open.blue, fill.blue, accuracy: 0.000_000_1)
    }

    func testLabelContrastsCrossNearAShownLuminanceOf0206() {
        var low = 0.0
        var high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            let surface = WallpaperSolidColor(red: mid, green: mid, blue: mid)
            let light = contrast(Ink.light.label, on: surface)
            let dark = contrast(Ink.dark.label, on: surface)
            if light > dark {
                low = mid
            } else {
                high = mid
            }
        }
        let crossed = (low + high) / 2
        let surface = WallpaperSolidColor(red: crossed, green: crossed, blue: crossed)
        let luminance = InkContrast.relativeLuminance(surface)
        XCTAssertEqual(luminance, 0.206, accuracy: 0.002)
        XCTAssertEqual(contrast(Ink.light.label, on: surface), contrast(Ink.dark.label, on: surface), accuracy: 0.01)
        XCTAssertLessThan(contrast(Ink.light.label, on: surface), InkContrast.textMinimum)
        XCTAssertLessThan(contrast(Ink.dark.label, on: surface), InkContrast.textMinimum)
    }

    func testPinnedFillsChooseInkAndVeilFromTheShownColour() {
        let peach = InkContrast.forFill(rgb(0xFFCBA4))
        XCTAssertEqual(peach.ink, .dark)
        XCTAssertEqual(peach.veil, WallpaperDim.black)

        let grey = InkContrast.forFill(rgb(0x808080))
        XCTAssertEqual(grey.ink, .light)
        XCTAssertEqual(grey.veil, WallpaperDim.black)

        let pale = InkContrast.forFill(rgb(0xE6E8EB))
        XCTAssertEqual(pale.ink, .dark)
        XCTAssertEqual(pale.veil, WallpaperDim.black)

        let charcoal = InkContrast.forFill(rgb(0x303238))
        XCTAssertEqual(charcoal.ink, .light)
        XCTAssertEqual(charcoal.veil, WallpaperDim.black)

        let rose = InkContrast.forFill(rgb(0xC9A0A6))
        XCTAssertEqual(rose.ink, .light)
        XCTAssertGreaterThan(rose.veil, WallpaperDim.black)
        XCTAssertEqual(rose.veil, 0.303, accuracy: 0.005)
        let roseShown = InkContrast.shown(rgb(0xC9A0A6), veil: rose.veil)
        let roseContrast = contrast(Ink.light.label, on: roseShown)
        XCTAssertGreaterThanOrEqual(roseContrast, InkContrast.textMinimum)
        XCTAssertLessThan(roseContrast, 4.55)

        let sky = InkContrast.forFill(rgb(0x7DAAD1))
        XCTAssertEqual(sky.ink, .light)
        XCTAssertGreaterThan(sky.veil, WallpaperDim.black)
        XCTAssertEqual(sky.veil, 0.281, accuracy: 0.005)
        let skyShown = InkContrast.shown(rgb(0x7DAAD1), veil: sky.veil)
        let skyContrast = contrast(Ink.light.label, on: skyShown)
        XCTAssertGreaterThanOrEqual(skyContrast, InkContrast.textMinimum)
        XCTAssertLessThan(skyContrast, 4.55)
    }

    func testFlatFillsIgnoreThePreviousInk() {
        let fills = sweepFills()
        for fill in fills {
            let solidLight = Ink.forBackdrop(.solidColor(fill), previous: .light)
            let solidDark = Ink.forBackdrop(.solidColor(fill), previous: .dark)
            XCTAssertEqual(solidLight, solidDark)
            let neutralLight = Ink.forBackdrop(.neutralFill(fill), previous: .light)
            let neutralDark = Ink.forBackdrop(.neutralFill(fill), previous: .dark)
            XCTAssertEqual(neutralLight, neutralDark)
            XCTAssertEqual(solidLight, neutralLight)
            XCTAssertEqual(InkContrast.forFill(fill).ink, solidLight)
            let again = InkContrast.forFill(fill)
            XCTAssertEqual(again.veil, InkContrast.forFill(fill).veil)
            XCTAssertEqual(again.ink, InkContrast.forFill(fill).ink)
        }
        XCTAssertEqual(Ink.forBackdrop(.picture, previous: .dark), .light)
        XCTAssertEqual(Ink.forBackdrop(.picture, previous: .light), .light)
    }

    func testSweepOfFillsMeetsLabelPlaceholderAndDotContrast() {
        let fills = sweepFills()
        XCTAssertGreaterThanOrEqual(fills.count, 500)
        var worstLabel = 99.0
        var worstPlaceholder = 99.0
        var worstTyped = 99.0
        var worstCaret = 99.0
        var worstInactive = 99.0
        var worstCurrent = 99.0
        for fill in fills {
            let choice = InkContrast.forFill(fill)
            let surface = InkContrast.shown(fill, veil: choice.veil)
            let ink = choice.ink
            worstLabel = min(worstLabel, contrast(ink.label, on: surface))
            let field = InkContrast.composite(ink.searchPill, over: surface)
            let placeholder = InkContrast.composite(ink.searchPlaceholder, over: solid(field))
            worstPlaceholder = min(worstPlaceholder, contrast(placeholder, on: field))
            worstTyped = min(worstTyped, contrast(InkContrast.composite(ink.searchText, over: solid(field)), on: field))
            worstCaret = min(worstCaret, contrast(InkContrast.composite(ink.searchCaret, over: solid(field)), on: field))
            let inactive = InkContrast.composite(ink.pageDot(distance: 1), over: surface)
            let current = InkContrast.composite(ink.pageDot(distance: 0), over: surface)
            worstInactive = min(worstInactive, contrast(inactive, on: surface))
            worstCurrent = min(worstCurrent, contrast(current, on: surface))
            XCTAssertGreaterThan(ink.pageDot(distance: 0).opacity, ink.pageDot(distance: 1).opacity + 0.2)
        }
        XCTAssertGreaterThanOrEqual(worstLabel, InkContrast.textMinimum)
        XCTAssertGreaterThanOrEqual(worstPlaceholder, InkContrast.textMinimum)
        XCTAssertGreaterThanOrEqual(worstTyped, InkContrast.textMinimum)
        XCTAssertGreaterThanOrEqual(worstCaret, InkContrast.textMinimum)
        XCTAssertGreaterThanOrEqual(worstInactive, InkContrast.graphicMinimum)
        XCTAssertGreaterThanOrEqual(worstCurrent, InkContrast.graphicMinimum)
    }

    func testSearchAndDotStrengthAreTheLowestHundredthsThatPass() {
        let fills = sweepFills()
        XCTAssertGreaterThanOrEqual(
            minimumPlaceholder(fills, lightScrim: Ink.lightSearchScrim, darkScrim: Ink.darkSearchScrim, darkOpacity: Ink.darkMutedOpacity),
            InkContrast.textMinimum
        )
        XCTAssertLessThan(
            minimumPlaceholder(fills, lightScrim: Ink.lightSearchScrim - 0.01, darkScrim: Ink.darkSearchScrim, darkOpacity: Ink.darkMutedOpacity),
            InkContrast.textMinimum
        )
        XCTAssertLessThan(
            minimumPlaceholder(fills, lightScrim: Ink.lightSearchScrim, darkScrim: Ink.darkSearchScrim - 0.01, darkOpacity: Ink.darkMutedOpacity),
            InkContrast.textMinimum
        )
        XCTAssertLessThan(
            minimumPlaceholder(fills, lightScrim: Ink.lightSearchScrim, darkScrim: Ink.darkSearchScrim, darkOpacity: Ink.darkMutedOpacity - 0.01),
            InkContrast.textMinimum
        )
        XCTAssertGreaterThanOrEqual(minimumDot(fills, opacity: Ink.pageDotInactiveOpacity), InkContrast.graphicMinimum)
        XCTAssertLessThan(minimumDot(fills, opacity: Ink.pageDotInactiveOpacity - 0.01), InkContrast.graphicMinimum)
        XCTAssertGreaterThanOrEqual(minimumDot(fills, opacity: Ink.pageDotCurrentOpacity), InkContrast.graphicMinimum)
    }

    private func rgb(_ hex: Int) -> WallpaperSolidColor {
        WallpaperSolidColor(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    private func solid(_ color: InkColor) -> WallpaperSolidColor {
        WallpaperSolidColor(red: color.red, green: color.green, blue: color.blue)
    }

    private func contrast(_ foreground: InkColor, on background: WallpaperSolidColor) -> Double {
        InkContrast.contrastRatio(
            InkContrast.relativeLuminance(foreground),
            against: InkContrast.relativeLuminance(background)
        )
    }

    private func contrast(_ foreground: InkColor, on background: InkColor) -> Double {
        InkContrast.contrastRatio(
            InkContrast.relativeLuminance(foreground),
            against: InkContrast.relativeLuminance(background)
        )
    }

    /// Grey ramp, a hue wheel at several lightnesses, and the fills that sit
    /// nearest the contrast boundary. About 500 colours.
    private func sweepFills() -> [WallpaperSolidColor] {
        var fills: [WallpaperSolidColor] = []
        for step in 0...64 {
            let channel = Double(step) / 64
            fills.append(WallpaperSolidColor(red: channel, green: channel, blue: channel))
        }
        let lightnesses = [0.18, 0.30, 0.42, 0.50, 0.58, 0.68, 0.78, 0.90]
        for lightness in lightnesses {
            for saturation in [0.5, 1.0] {
                for step in 0..<28 {
                    fills.append(hsl(hue: Double(step) * (360.0 / 28.0), saturation: saturation, lightness: lightness))
                }
            }
        }
        fills.append(WallpaperSolidColor(red: 1, green: 0.3245, blue: 1))
        fills.append(WallpaperSolidColor(red: 0, green: 0.8047, blue: 0))
        fills.append(WallpaperSolidColor(red: 1, green: 0, blue: 0))
        fills.append(WallpaperSolidColor(red: 0, green: 1, blue: 0))
        fills.append(WallpaperSolidColor(red: 0, green: 0, blue: 1))
        fills.append(WallpaperSolidColor(red: 1, green: 1, blue: 1))
        fills.append(WallpaperSolidColor(red: 0, green: 0, blue: 0))
        return fills
    }

    private func hsl(hue: Double, saturation: Double, lightness: Double) -> WallpaperSolidColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = hue.truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2
        let red: Double
        let green: Double
        let blue: Double
        if sector < 1 {
            red = chroma
            green = x
            blue = 0
        } else if sector < 2 {
            red = x
            green = chroma
            blue = 0
        } else if sector < 3 {
            red = 0
            green = chroma
            blue = x
        } else if sector < 4 {
            red = 0
            green = x
            blue = chroma
        } else if sector < 5 {
            red = x
            green = 0
            blue = chroma
        } else {
            red = chroma
            green = 0
            blue = x
        }
        return WallpaperSolidColor(red: red + match, green: green + match, blue: blue + match)
    }

    private func minimumPlaceholder(
        _ fills: [WallpaperSolidColor],
        lightScrim: Double,
        darkScrim: Double,
        darkOpacity: Double
    ) -> Double {
        var worst = 99.0
        for fill in fills {
            let choice = InkContrast.forFill(fill)
            let surface = InkContrast.shown(fill, veil: choice.veil)
            let scrim: InkColor
            let placeholder: InkColor
            switch choice.ink {
            case .light:
                scrim = .black(opacity: lightScrim)
                placeholder = .white(opacity: 0.65)
            case .dark:
                scrim = .white(opacity: darkScrim)
                placeholder = Ink.dark.label.opacity(darkOpacity)
            }
            let field = InkContrast.composite(scrim, over: surface)
            worst = min(worst, contrast(InkContrast.composite(placeholder, over: solid(field)), on: field))
        }
        return worst
    }

    private func minimumDot(_ fills: [WallpaperSolidColor], opacity: Double) -> Double {
        var worst = 99.0
        for fill in fills {
            let choice = InkContrast.forFill(fill)
            let surface = InkContrast.shown(fill, veil: choice.veil)
            let dot = choice.ink.label.opacity(opacity)
            worst = min(worst, contrast(InkContrast.composite(dot, over: surface), on: surface))
        }
        return worst
    }
}
