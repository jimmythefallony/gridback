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

    /// Pictures and solid colours stay light. The neutral fill follows its luminance.
    /// Two thresholds leave a gap: inside the gap the previous ink stays, so a fill
    /// that jitters near one boundary cannot flip back and forth.
    public static func forBackdrop(_ source: BackdropInkSource, previous: Ink) -> Ink {
        switch source {
        case .picture, .solidColor:
            return .light
        case .neutralFill(let fill):
            return forLuminance(InkContrast.relativeLuminance(fill), previous: previous)
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
    public var muted: InkColor { swatch.opacity(0.65) }

    public var hoverHighlight: InkColor { swatch.opacity(0.16) }
    public var selectionHighlight: InkColor { swatch.opacity(0.28) }
    public var dropRing: InkColor { swatch.opacity(0.9) }
    public var searchPill: InkColor { swatch.opacity(0.16) }
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

    /// Page dot opacity follows distance from the current page, from 0.95 down to 0.33.
    public func pageDot(distance: Double) -> InkColor {
        swatch.opacity(0.95 - distance * 0.62)
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
public enum BackdropInkSource: Equatable, Sendable {
    case picture
    case solidColor
    case neutralFill(WallpaperSolidColor)

    /// A real picture wins. A solid colour is next. Anything else is the neutral fill.
    public static func resolve(hasPicture: Bool, isSolidColor: Bool, fill: WallpaperSolidColor) -> BackdropInkSource {
        if hasPicture { return .picture }
        if isSolidColor { return .solidColor }
        return .neutralFill(fill)
    }
}

/// WCAG 2 relative luminance and contrast. Translucent ink is composited over the fill first.
public enum InkContrast {
    public static let textMinimum = 4.5
    public static let graphicMinimum = 3.0
    /// At or below this, the fill takes light ink. White text is clearly the readable one here.
    public static let lightInkLuminance = 0.15
    /// At or above this, the fill takes dark ink. Dark text is clearly the readable one here.
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
