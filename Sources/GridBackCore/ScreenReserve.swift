import Foundation

/// Space the menu bar and Dock are occupying inside one display.
///
/// Coordinates match AppKit: origin at the bottom left, y growing upward.
/// `top` is the menu bar. `left`, `bottom`, and `right` are the Dock when it
/// is reserving that edge. An auto-hidden Dock does not shrink the visible
/// frame, so those edges stay zero and the preference is left unchanged.
public struct ScreenReserve: Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public static let none = ScreenReserve(top: 0, left: 0, bottom: 0, right: 0)

    /// The menu bar is auto-hidden when `visibleFrame` still reaches the top
    /// of the screen. A positive `top` means it is reserving space.
    public var menuBarReservesSpace: Bool {
        top > 0.5
    }

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    /// Insets of `visible` inside `screen`. Negative differences clamp to zero.
    public static func occupying(
        screenX: Double,
        screenY: Double,
        screenWidth: Double,
        screenHeight: Double,
        visibleX: Double,
        visibleY: Double,
        visibleWidth: Double,
        visibleHeight: Double
    ) -> ScreenReserve {
        let screenMaxX = screenX + screenWidth
        let screenMaxY = screenY + screenHeight
        let visibleMaxX = visibleX + visibleWidth
        let visibleMaxY = visibleY + visibleHeight
        return ScreenReserve(
            top: max(0, screenMaxY - visibleMaxY),
            left: max(0, visibleX - screenX),
            bottom: max(0, visibleY - screenY),
            right: max(0, screenMaxX - visibleMaxX)
        )
    }
}

/// AppKit presentation bits. Hiding the menu bar with `NSMenu.setMenuBarVisible(false)`
/// also sets `hideDock`. These helpers never introduce a Dock-hide bit.
public enum MenuBarPresentation {
    public static let autoHideDock: UInt = 1 << 0
    public static let hideDock: UInt = 1 << 1
    public static let autoHideMenuBar: UInt = 1 << 2
    public static let hideMenuBar: UInt = 1 << 3

    /// While the menu bar is auto-hidden, ask for that behavior alone.
    /// A menu bar that already reserves space is left unchanged.
    public static func keepingDockVisible(current: UInt, suppressAutoHiddenMenuBar: Bool) -> UInt {
        guard suppressAutoHiddenMenuBar else { return current }
        var next = current | autoHideMenuBar
        next &= ~hideMenuBar
        if current & hideDock == 0 {
            next &= ~hideDock
        }
        if current & autoHideDock == 0 {
            next &= ~autoHideDock
        }
        return next
    }
}
