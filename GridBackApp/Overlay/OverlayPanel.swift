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
    let fallbackBlur = NSVisualEffectView()

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
        BackdropSurface.prepare(imageView: backdropView, fallback: fallbackBlur, in: self)
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
    let fallbackBlur = NSVisualEffectView()

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
        BackdropSurface.prepare(imageView: backdropView, fallback: fallbackBlur, in: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum BackdropSurface {
    static func prepare(imageView: NSImageView, fallback: NSVisualEffectView, in window: NSWindow) {
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        fallback.material = .fullScreenUI
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        fallback.isHidden = true
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        container.clipsToBounds = true
        container.addSubview(imageView)
        window.contentView = container
    }

    /// Places one full-screen picture in `window`'s coordinates. The material is
    /// not in the hierarchy while that picture is showing, so it cannot tint it.
    static func show(image: NSImage?, placement: NSRect, imageView: NSImageView, fallback: NSVisualEffectView, window: NSWindow) {
        guard let image else {
            imageView.image = nil
            imageView.isHidden = true
            let container = window.contentView
            fallback.frame = container?.bounds ?? placement
            fallback.autoresizingMask = [.width, .height]
            if fallback.superview == nil {
                container?.addSubview(fallback, positioned: .below, relativeTo: nil)
            }
            fallback.isHidden = false
            window.isOpaque = false
            window.backgroundColor = .clear
            return
        }
        fallback.isHidden = true
        fallback.removeFromSuperview()
        imageView.isHidden = false
        imageView.frame = placement
        imageView.image = image
        window.isOpaque = true
        window.backgroundColor = .black
    }
}
