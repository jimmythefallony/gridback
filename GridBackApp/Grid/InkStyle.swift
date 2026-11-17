import AppKit
import GridBackCore
import SwiftUI

extension InkColor {
    /// Fully opaque white and black stay the system colours, so light ink
    /// draws the same pixels the grid drew before this indirection.
    var color: Color {
        switch self {
        case let .white(opacity):
            return opacity == 1 ? Color.white : Color.white.opacity(opacity)
        case let .black(opacity):
            return opacity == 1 ? Color.black : Color.black.opacity(opacity)
        case let .srgb(red, green, blue, opacity):
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
        }
    }

    var nsColor: NSColor {
        switch self {
        case let .white(opacity):
            if opacity == 1 { return .white }
            return NSColor.white.withAlphaComponent(CGFloat(opacity))
        case let .black(opacity):
            if opacity == 1 { return .black }
            return NSColor.black.withAlphaComponent(CGFloat(opacity))
        case let .srgb(red, green, blue, opacity):
            return NSColor(
                srgbRed: CGFloat(red),
                green: CGFloat(green),
                blue: CGFloat(blue),
                alpha: CGFloat(opacity)
            )
        }
    }
}

extension InkWindowAppearance {
    var nsAppearanceName: NSAppearance.Name {
        switch self {
        case .darkAqua:
            return .darkAqua
        case .aqua:
            return .aqua
        }
    }
}

private struct InkKey: EnvironmentKey {
    static let defaultValue = Ink.light
}

extension EnvironmentValues {
    var ink: Ink {
        get { self[InkKey.self] }
        set { self[InkKey.self] = newValue }
    }
}

extension View {
    /// Draws a label shadow when the ink has one. A missing shadow is invisible.
    func gridTextShadow(_ shadow: InkShadow?) -> some View {
        self.shadow(
            color: shadow?.color.color ?? Color.clear,
            radius: CGFloat(shadow?.radius ?? 0),
            y: CGFloat(shadow?.y ?? 0)
        )
    }
}
