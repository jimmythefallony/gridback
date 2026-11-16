import Foundation

/// Foreground ink for the grid.
///
/// Light ink is the white-on-dark look the app draws today.
/// Dark ink is the near-black set for a light backdrop. The app does not select it yet.
public enum Ink: Equatable, Sendable {
    case light
    case dark

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
