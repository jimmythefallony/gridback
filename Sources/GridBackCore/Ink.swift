import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Foreground ink for the grid.
///
/// Light ink is the white-on-dark look. Dark ink is the near-black set for the pale neutral fill.
public enum Ink: Equatable, Sendable {
    case light
    case dark

    /// Pictures stay light. A solid colour or a neutral fill takes the ink for
    /// that fill as shown, after the veil. Flat fills do not remember the
    /// previous ink. `forLuminance` still does; that gap is for a later photo step.
    public static func forBackdrop(_ source: BackdropInkSource, previous _: Ink) -> Ink {
        switch source {
        case .picture:
            return .light
        case .solidColor(let fill), .neutralFill(let fill):
            return InkContrast.forFill(fill).ink
        }
    }

    /// Light ink at or below the low threshold, dark ink at or above the high one, previous ink between them.
    public static func forLuminance(_ luminance: Double, previous: Ink) -> Ink {
        if luminance >= InkContrast.darkInkLuminance {
            return .dark
        }
        if luminance <= InkContrast.lightInkLuminance {
            return .light
        }
        return previous
    }

    public var label: InkColor { swatch.opacity(1) }

    /// Shadow under app labels and names on a folder tile. Nil when the ink needs none.
    public var labelShadow: InkShadow? {
        switch self {
        case .light:
            return InkShadow(color: .black(opacity: 0.45), radius: 2, y: 1)
        case .dark:
            return nil
        }
    }

    /// Shadow under the open folder's title. Nil when the ink needs none.
    public var folderTitleShadow: InkShadow? {
        switch self {
        case .light:
            return InkShadow(color: .black(opacity: 0.35), radius: 2, y: 1)
        case .dark:
            return nil
        }
    }

    /// Empty search copy and the dashed icon that stands in for a missing app.
    public var quiet: InkColor { swatch.opacity(0.85) }

    /// Search placeholder, magnifying glass, and other quieter foreground.
    /// Dark ink needs a stronger tone. 0.65 stays under 4.5:1 on a pale fill.
    public var muted: InkColor {
        switch self {
        case .light:
            return swatch.opacity(0.65)
        case .dark:
            return swatch.opacity(Self.darkMutedOpacity)
        }
    }

    public var hoverHighlight: InkColor { swatch.opacity(0.16) }
    public var selectionHighlight: InkColor { swatch.opacity(0.28) }
    public var dropRing: InkColor { swatch.opacity(0.9) }

    /// Capsule behind the search field. It moves away from the ink: black under
    /// white text, white under dark text. A wash of the ink colour lifts the
    /// field toward the letters and the placeholder falls under 4.5:1.
    public var searchPill: InkColor {
        switch self {
        case .light:
            return .black(opacity: Self.lightSearchScrim)
        case .dark:
            return .white(opacity: Self.darkSearchScrim)
        }
    }
    public var searchText: InkColor { label }
    public var searchPlaceholder: InkColor { muted }
    public var searchCaret: InkColor { label }
    public var folderPanelFill: InkColor { swatch.opacity(0.24) }
    public var folderPanelStroke: InkColor { swatch.opacity(0.45) }

    public func iconHighlight(selected: Bool, hovering: Bool) -> InkColor {
        if selected { return selectionHighlight }
        if hovering { return hoverHighlight }
        return swatch.opacity(0)
    }

    public func folderFill(armed: Bool) -> InkColor {
        swatch.opacity(armed ? 0.28 : 0.16)
    }

    public func folderStroke(armed: Bool) -> InkColor {
        swatch.opacity(armed ? 0.95 : 0.28)
    }

    /// Page dot opacity follows distance from the current page, from 0.95 down to 0.72.
    /// 0.72 is the lowest hundredth at which a far dot still reaches 3:1 on every flat fill.
    /// The current dot stays stronger so the two remain easy to tell apart.
    public func pageDot(distance: Double) -> InkColor {
        let current = Self.pageDotCurrentOpacity
        let inactive = Self.pageDotInactiveOpacity
        return swatch.opacity(current - distance * (current - inactive))
    }

    public func pageArrow(enabled: Bool) -> InkColor {
        swatch.opacity(enabled ? 0.9 : 0.28)
    }

    /// Light ink keeps both grid windows on dark Aqua.
    public var windowAppearance: InkWindowAppearance {
        switch self {
        case .light:
            return .darkAqua
        case .dark:
            return .aqua
        }
    }

    /// Black scrim under white search text. Lowest hundredth that keeps a 0.65
    /// white placeholder at 4.5:1 on every fill that takes light ink.
    public static let lightSearchScrim = 0.35
    /// White scrim under dark search text. A dark scrim would pull a barely-readable
    /// fill toward the ink. Lowest hundredth that lets the 0.80 placeholder reach 4.5:1.
    public static let darkSearchScrim = 0.26
    /// Lowest hundredth for the dark placeholder and magnifying glass.
    public static let darkMutedOpacity = 0.80
    public static let pageDotCurrentOpacity = 0.95
    public static let pageDotInactiveOpacity = 0.72

    private var swatch: InkColor {
        switch self {
        case .light:
            return .white(opacity: 1)
        case .dark:
            return .srgb(
                red: Double(0x1D) / 255,
                green: Double(0x1D) / 255,
                blue: Double(0x1F) / 255,
                opacity: 1
            )
        }
    }
}

/// A grid colour as plain components, so tests can pin it without AppKit.
public enum InkColor: Equatable, Sendable {
    case white(opacity: Double)
    case black(opacity: Double)
    case srgb(red: Double, green: Double, blue: Double, opacity: Double)

    public var red: Double {
        switch self {
        case .white:
            return 1
        case .black:
            return 0
        case let .srgb(red, _, _, _):
            return red
        }
    }

    public var green: Double {
        switch self {
        case .white:
            return 1
        case .black:
            return 0
        case let .srgb(_, green, _, _):
            return green
        }
    }

    public var blue: Double {
        switch self {
        case .white:
            return 1
        case .black:
            return 0
        case let .srgb(_, _, blue, _):
            return blue
        }
    }

    public var opacity: Double {
        switch self {
        case let .white(opacity), let .black(opacity):
            return opacity
        case let .srgb(_, _, _, opacity):
            return opacity
        }
    }

    public func opacity(_ opacity: Double) -> InkColor {
        switch self {
        case .white:
            return .white(opacity: opacity)
        case .black:
            return .black(opacity: opacity)
        case let .srgb(red, green, blue, _):
            return .srgb(red: red, green: green, blue: blue, opacity: opacity)
        }
    }
}

public struct InkShadow: Equatable, Sendable {
    public var color: InkColor
    public var radius: Double
    public var y: Double

    public init(color: InkColor, radius: Double, y: Double) {
        self.color = color
        self.radius = radius
        self.y = y
    }
}

/// Window appearance that goes with an ink. The app target maps this onto `NSAppearance`.
public enum InkWindowAppearance: Equatable, Sendable {
    case darkAqua
    case aqua
}

/// What is behind the grid, for choosing ink.
/// `picture` is a matched frame (a still, or an Aerial frame when one is shown).
/// A solid colour carries the fill the veil is applied to.
public enum BackdropInkSource: Equatable, Sendable {
    case picture
    case solidColor(WallpaperSolidColor)
    case neutralFill(WallpaperSolidColor)

    /// A real picture wins. A solid colour is next. Anything else is the neutral fill.
    public static func resolve(hasPicture: Bool, isSolidColor: Bool, fill: WallpaperSolidColor) -> BackdropInkSource {
        if hasPicture { return .picture }
        if isSolidColor { return .solidColor(fill) }
        return .neutralFill(fill)
    }
}

/// Ink for a flat fill, and the black veil actually drawn over that fill.
public struct FillInk: Equatable, Sendable {
    public var ink: Ink
    public var veil: Double

    public init(ink: Ink, veil: Double) {
        self.ink = ink
        self.veil = veil
    }
}

/// WCAG 2 relative luminance and contrast. Translucent ink is composited over the fill first.
public enum InkContrast {
    public static let textMinimum = 4.5
    public static let graphicMinimum = 3.0
    /// `forLuminance` takes light ink at or below this. Flat fills do not use it.
    public static let lightInkLuminance = 0.15
    /// `forLuminance` takes dark ink at or above this. Between the two, the previous ink stays.
    public static let darkInkLuminance = 0.30

    public static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func relativeLuminance(_ color: InkColor) -> Double {
        relativeLuminance(red: color.red, green: color.green, blue: color.blue)
    }

    public static func relativeLuminance(_ color: WallpaperSolidColor) -> Double {
        relativeLuminance(red: color.red, green: color.green, blue: color.blue)
    }

    public static func contrastRatio(_ foreground: Double, against background: Double) -> Double {
        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The fill after a black veil. Each channel is `fill * (1 - veil)`.
    /// The default veil is the normal one. Flat-fill decisions pass the veil
    /// they actually draw, including the darker veil in the mid-tone band.
    public static func shown(_ fill: WallpaperSolidColor, veil: Double = WallpaperDim.black) -> WallpaperSolidColor {
        let keep = 1 - veil
        return WallpaperSolidColor(
            red: fill.red * keep,
            green: fill.green * keep,
            blue: fill.blue * keep
        )
    }

    /// Ink and veil for one flat fill. Photos do not come through here.
    ///
    /// Decide from the colour as shown, not the raw wallpaper colour.
    /// The same fill always returns the same ink and veil. There is no gap
    /// and no use of the previous ink.
    ///
    /// White and dark labels are equally readable at a shown luminance of
    /// about 0.206. Neither reaches 4.5:1 under the normal 25% veil between
    /// about 0.183 (white) and about 0.231 (dark).
    ///
    /// Dark ink is used only when it already reaches 4.5:1 on the colour
    /// shown at the normal veil, and that veil stays put. Every other fill
    /// uses light ink, which keeps its label shadow. If white does not reach
    /// 4.5:1 at the normal veil, the veil rises to the smallest value that
    /// does. That extra amount is zero at the dark edge of the band and grows
    /// continuously with the fill, so a colour just inside the band does not
    /// step darker than its neighbour. The veil returns to the normal amount
    /// only once dark ink is readable: no shown colour lets both inks reach
    /// 4.5:1, so the backdrop has to lighten when the ink switches.
    public static func forFill(_ fill: WallpaperSolidColor) -> FillInk {
        let normal = WallpaperDim.black
        let atNormal = shown(fill, veil: normal)
        if labelContrast(.dark, on: atNormal) >= textMinimum {
            return FillInk(ink: .dark, veil: normal)
        }
        return FillInk(ink: .light, veil: veilForLightLabel(fill, floor: normal))
    }

    /// Smallest veil at or above `floor` at which a white label reaches 4.5:1.
    private static func veilForLightLabel(_ fill: WallpaperSolidColor, floor: Double) -> Double {
        if labelContrast(.light, on: shown(fill, veil: floor)) >= textMinimum {
            return floor
        }
        var low = floor
        var high = 1.0
        for _ in 0..<48 {
            let mid = (low + high) / 2
            if labelContrast(.light, on: shown(fill, veil: mid)) >= textMinimum {
                high = mid
            } else {
                low = mid
            }
        }
        return high
    }

    private static func labelContrast(_ ink: Ink, on surface: WallpaperSolidColor) -> Double {
        contrastRatio(relativeLuminance(ink.label), against: relativeLuminance(surface))
    }

    /// Source-over of a translucent ink on an opaque fill. The result is opaque.
    public static func composite(_ foreground: InkColor, over background: WallpaperSolidColor) -> InkColor {
        let alpha = min(max(foreground.opacity, 0), 1)
        return .srgb(
            red: foreground.red * alpha + background.red * (1 - alpha),
            green: foreground.green * alpha + background.green * (1 - alpha),
            blue: foreground.blue * alpha + background.blue * (1 - alpha),
            opacity: 1
        )
    }

    /// WCAG 2 sRGB channel. The split is the one written in the contrast definition.
    private static func linear(_ channel: Double) -> Double {
        let value = min(max(channel, 0), 1)
        if value <= 0.03928 {
            return value / 12.92
        }
        return pow((value + 0.055) / 1.055, 2.4)
    }
}

/// How long the backdrop and the ink take to move together while the grid is open.
public enum InkCrossfade {
    public static let duration = 0.25
}
