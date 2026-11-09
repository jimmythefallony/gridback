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

/// Whether the grid should keep the menu bar from staying revealed.
/// A bar that is only popped open still counts as auto-hidden when that is the user's preference.
public enum MenuBarSuppression {
    public static func shouldSuppress(menuBarReservesSpace: Bool, userAutoHidesMenuBar: Bool) -> Bool {
        userAutoHidesMenuBar || !menuBarReservesSpace
    }
}

public enum DockEdge: Equatable, Sendable {
    case bottom, left, right
}

/// How much of the screen the high grid window must leave uncovered so the Dock,
/// including a magnified icon, stays above it.
public struct DockOcclusion: Equatable, Sendable {
    public var edge: DockEdge
    public var thickness: Double

    public init(edge: DockEdge, thickness: Double) {
        self.edge = edge
        self.thickness = thickness
    }

    /// Resting Dock height estimated from the icon tile when auto-hide reserves nothing.
    /// 64 pt tiles land on the 90 pt band this display uses when the Dock is showing.
    public static func autoHideThickness(tileSize: Double) -> Double {
        (max(tileSize, 16) * 1.4).rounded()
    }

    /// Used when magnification is on and `largesize` has never been written.
    public static let defaultMagnifiedSize: Double = 128

    public static func largeSize(stored: Double?, magnificationEnabled: Bool) -> Double {
        if let stored, stored > 0 { return stored }
        return magnificationEnabled ? defaultMagnifiedSize : 0
    }

    /// The Dock's magnified-icon name bubble is about 22–30 pt tall.
    public static let magnifiedLabelHeight: Double = 28
    /// Gap under the bubble, plus a little room so it does not touch the grid.
    public static let magnifiedLabelMargin: Double = 12

    /// Extra reach past the resting band while magnification is on: the icon's
    /// growth, then the name label above it. `largesize + label + margin` is the
    /// same reach measured from the screen edge when the resting band is the tile.
    public static func magnificationOverflow(enabled: Bool, tileSize: Double, largeSize: Double) -> Double {
        guard enabled else { return 0 }
        let iconGrowth = max(0, largeSize - max(tileSize, 0))
        return iconGrowth + magnifiedLabelHeight + magnifiedLabelMargin
    }

    public static func snapped(_ points: Double, scale: Double) -> Double {
        let scale = max(scale, 1)
        return (points * scale).rounded() / scale
    }

    /// Prefer the edge `visibleFrame` is already reserving. Auto-hide has no inset,
    /// so the estimated band is used instead. Magnification is added on that edge.
    public static func resolve(
        reserve: ScreenReserve,
        autoHides: Bool,
        autoHideEdge: DockEdge,
        estimatedAutoHideThickness: Double,
        magnificationOverflow: Double,
        scale: Double
    ) -> DockOcclusion {
        let reserved: [(DockEdge, Double)] = [
            (.bottom, reserve.bottom),
            (.left, reserve.left),
            (.right, reserve.right)
        ]
        let resting: (DockEdge, Double)
        if let edge = reserved.max(by: { $0.1 < $1.1 }), edge.1 > 0.5 {
            resting = edge
        } else if autoHides {
            resting = (autoHideEdge, max(estimatedAutoHideThickness, 0))
        } else {
            resting = (.bottom, 0)
        }
        let thickness = snapped(resting.1 + max(0, magnificationOverflow), scale: scale)
        return DockOcclusion(edge: resting.0, thickness: max(0, thickness))
    }
}

public struct PlacedRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The interactive grid covers the menu bar and stops at the Dock.
/// The backdrop is the full screen, behind the Dock, showing the same picture.
public struct GridOverlayFrames: Equatable, Sendable {
    public var grid: PlacedRect
    public var backdrop: PlacedRect

    public init(grid: PlacedRect, backdrop: PlacedRect) {
        self.grid = grid
        self.backdrop = backdrop
    }

    public static func make(
        screenX: Double,
        screenY: Double,
        screenWidth: Double,
        screenHeight: Double,
        occlusion: DockOcclusion
    ) -> GridOverlayFrames {
        let width = max(screenWidth, 0)
        let height = max(screenHeight, 0)
        let backdrop = PlacedRect(x: screenX, y: screenY, width: width, height: height)
        let span = occlusion.edge == .bottom ? height : width
        let thickness = min(max(occlusion.thickness, 0), max(span - 1, 0))
        let grid: PlacedRect
        switch occlusion.edge {
        case .bottom:
            grid = PlacedRect(x: screenX, y: screenY + thickness, width: width, height: height - thickness)
        case .left:
            grid = PlacedRect(x: screenX + thickness, y: screenY, width: width - thickness, height: height)
        case .right:
            grid = PlacedRect(x: screenX, y: screenY, width: width - thickness, height: height)
        }
        return GridOverlayFrames(grid: grid, backdrop: backdrop)
    }
}

/// Where the full-screen picture sits inside a window so both windows share pixels.
/// AppKit origin is the bottom left. A window that starts above the Dock shifts the
/// picture down by that same amount.
public struct BackdropImagePlacement: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func inWindow(screen: PlacedRect, window: PlacedRect) -> BackdropImagePlacement {
        BackdropImagePlacement(
            x: screen.x - window.x,
            y: screen.y - window.y,
            width: screen.width,
            height: screen.height
        )
    }
}
