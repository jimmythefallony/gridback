import AppKit
import GridBackCore

/// Borderless panel sized to one display. It joins existing Spaces, including a
/// full-screen app's Space, and does not become a full-screen Space of its own
/// (`fullScreenPrimary` is intentionally absent).
final class OverlayPanel: NSPanel {
    /// One level under the Dock, and still above normal and floating windows.
    ///
    /// The Dock process keeps drawing its own icons, size, order, magnification,
    /// and translucent background. This panel does not change Dock preferences
    /// or presentation options. The lock-screen shield stays above the grid.
    static var overlayLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.overlayLevel
        // macOS rejects canJoinAllSpaces together with moveToActiveSpace.
        // Joining every Space keeps the grid on the primary display, including
        // over a full-screen app, without pulling the window onto another display.
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false
        worksWhenModal = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        title = "GridBack"
        identifier = NSUserInterfaceItemIdentifier("GridBackOverlay")
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Paints over the menu bar only. The grid window stays under the Dock, so this
/// strip is a separate window above the menu bar and nowhere near the Dock.
final class MenuBarCoverPanel: NSPanel {
    /// Above the menu bar and status items. The Dock is level 20 and is not
    /// under this strip, so it stays visible.
    static var coverLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    }

    static func frame(on screen: NSScreen) -> NSRect {
        let revealed = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let height = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness, revealed, 24)
        let rect = MenuBarCoverFrame.rect(
            screenMinX: Double(screen.frame.minX),
            screenMinY: Double(screen.frame.minY),
            screenWidth: Double(screen.frame.width),
            screenHeight: Double(screen.frame.height),
            barHeight: Double(height)
        )
        return NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    init(screen: NSScreen) {
        super.init(
            contentRect: Self.frame(on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.coverLevel
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        worksWhenModal = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        title = "GridBack Menu Bar Cover"
        identifier = NSUserInterfaceItemIdentifier("GridBackMenuBarCover")
        appearance = NSAppearance(named: .darkAqua)
        ignoresMouseEvents = false

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.autoresizingMask = [.width, .height]
        let bounds = contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        imageView.frame = bounds
        contentView = imageView
    }

    /// Shows the desktop picture, blurred and lifted like the grid material.
    /// This window sits above the menu bar, so a live material would blur the bar instead.
    func show(snapshot: NSImage, on screen: NSScreen) {
        setFrame(Self.frame(on: screen), display: true)
        imageView.frame = contentView?.bounds ?? NSRect(origin: .zero, size: frame.size)
        imageView.image = snapshot
        level = Self.coverLevel
        orderFrontRegardless()
        level = Self.coverLevel
    }

    private let imageView = NSImageView()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
