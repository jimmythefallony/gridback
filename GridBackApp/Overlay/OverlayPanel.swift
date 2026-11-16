import AppKit
import GridBackCore

/// Borderless panel for the interactive grid. It joins existing Spaces, including
/// a full-screen app's Space, and does not become a full-screen Space of its own
/// (`fullScreenPrimary` is intentionally absent).
final class OverlayPanel: NSPanel {
    /// Above the menu bar (24) and status items (25). The frame stops at the Dock,
    /// so this does not cover the Dock even though 26 is above the Dock's 20.
    static var gridLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    }

    let backdropView = NSImageView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = Self.gridLevel
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
        ignoresMouseEvents = false
        BackdropSurface.prepare(imageView: backdropView, in: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen picture behind the Dock. Level is one below the Dock, and the
/// window does not accept clicks, so the Dock (including magnification) stays
/// in front and still receives them.
final class DockBackdropPanel: NSPanel {
    static var backdropLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
    }

    let backdropView = NSImageView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = false
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = Self.backdropLevel
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
        title = "GridBack Dock Backdrop"
        identifier = NSUserInterfaceItemIdentifier("GridBackDockBackdrop")
        appearance = NSAppearance(named: .darkAqua)
        ignoresMouseEvents = true
        BackdropSurface.prepare(imageView: backdropView, in: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum BackdropSurface {
    static func prepare(imageView: NSImageView, in window: NSWindow) {
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        container.clipsToBounds = true
        container.addSubview(imageView)
        window.contentView = container
    }

    /// Places the one shared picture in `window`'s coordinates. Both windows
    /// show this same image, so the grid and the Dock band stay aligned.
    /// Reduce Transparency does not change it: there is no live desktop sample.
    static func show(image: NSImage, placement: NSRect, imageView: NSImageView, window: NSWindow) {
        imageView.isHidden = false
        imageView.frame = placement
        imageView.image = image
        window.isOpaque = true
        window.backgroundColor = .black
    }
}
