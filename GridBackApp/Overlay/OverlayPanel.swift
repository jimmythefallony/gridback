import AppKit
import GridBackCore
import QuartzCore

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

    init(screen: NSScreen, ink: Ink) {
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
        ignoresMouseEvents = false
        BackdropSurface.prepare(imageView: backdropView, in: self)
        apply(ink: ink)
    }

    func apply(ink: Ink) {
        appearance = NSAppearance(named: ink.windowAppearance.nsAppearanceName)
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

    init(screen: NSScreen, ink: Ink) {
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
        ignoresMouseEvents = true
        BackdropSurface.prepare(imageView: backdropView, in: self)
        apply(ink: ink)
    }

    func apply(ink: Ink) {
        appearance = NSAppearance(named: ink.windowAppearance.nsAppearanceName)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum BackdropSurface {
    private static let fadeID = NSUserInterfaceItemIdentifier("GridBackBackdropFade")

    static func prepare(imageView: NSImageView, in window: NSWindow) {
        configure(imageView)
        let fade = NSImageView(frame: imageView.frame)
        configure(fade)
        fade.identifier = fadeID
        fade.alphaValue = 0
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.autoresizingMask = [.width, .height]
        container.clipsToBounds = true
        container.addSubview(imageView)
        container.addSubview(fade)
        window.contentView = container
    }

    /// Places the one shared picture in `window`'s coordinates. Both windows
    /// show this same image, so the grid and the Dock band stay aligned.
    /// Reduce Transparency does not change it: there is no live desktop sample.
    /// `crossfade` dissolves the new picture over the one already on screen.
    static func show(image: NSImage, placement: NSRect, imageView: NSImageView, window: NSWindow, crossfade: Bool) {
        imageView.isHidden = false
        window.isOpaque = true
        window.backgroundColor = .black
        let fadeView = fadeView(pairedWith: imageView)
        if crossfade, let fading = fadeView.image, fading === image, fadeView.alphaValue > 0 {
            imageView.frame = placement
            fadeView.frame = placement
            return
        }
        let token = fadeView.tag + 1
        fadeView.tag = token
        let sameImage = imageView.image.map { $0 === image } ?? false
        let animate = crossfade && imageView.image != nil && !sameImage
        guard animate else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fadeView.alphaValue = 0
            fadeView.image = nil
            imageView.alphaValue = 1
            imageView.frame = placement
            imageView.image = image
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if fadeView.alphaValue > 0, let current = fadeView.image {
            imageView.image = current
        }
        imageView.frame = placement
        fadeView.frame = placement
        fadeView.alphaValue = 0
        fadeView.image = image
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = InkCrossfade.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeView.animator().alphaValue = 1
        } completionHandler: { [weak imageView, weak fadeView] in
            guard let imageView, let fadeView, fadeView.tag == token else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageView.image = image
            fadeView.alphaValue = 0
            fadeView.image = nil
            CATransaction.commit()
        }
    }

    private static func configure(_ imageView: NSImageView) {
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private static func fadeView(pairedWith imageView: NSImageView) -> NSImageView {
        if let existing = imageView.superview?.subviews.compactMap({ $0 as? NSImageView }).first(where: {
            $0 !== imageView && $0.identifier == fadeID
        }) {
            return existing
        }
        let fade = NSImageView(frame: imageView.frame)
        configure(fade)
        fade.identifier = fadeID
        fade.alphaValue = 0
        imageView.superview?.addSubview(fade, positioned: .above, relativeTo: imageView)
        return fade
    }
}
