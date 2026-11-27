import AppKit
import ApplicationServices
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

    /// Notes a key, then passes the event on unchanged.
    override func sendEvent(_ event: NSEvent) {
        Issue4Log.notePanelSendEvent(event)
        super.sendEvent(event)
    }
}

/// Temporary prints. Does not change the drag or read the event queue.
enum Issue4Log {
    private static var didLogTrust = false
    private static var didLogStack = false

    static func dragStarted(kind: String) {
        Self.didLogStack = false
        Self.logTrustOnce()
        print("[#4] drag start kind=\(kind) \(Self.focus())")
    }

    static func dragNow(kind: String) {
        print("[#4] drag now kind=\(kind)")
    }

    static func dragEnded(kind: String, escapeRan: Bool) {
        let escape = escapeRan ? "yes" : "no"
        let mouseUpTs = Self.mouseUpTimestamp()
        print("[#4] drag end kind=\(kind) escape=\(escape) mouseUpTs=\(mouseUpTs)")
    }

    static func keyDown(place: String, code: UInt16, timestamp: TimeInterval, dragActive: Bool) {
        let active = dragActive ? "yes" : "no"
        let ts = Self.stamp(timestamp)
        print("[#4] keyDown where=\(place) code=\(code) ts=\(ts) dragActive=\(active)")
    }

    static func globalEscape() {
        print("[#4] global keyDown keyCode=53 \(Self.focus())")
    }

    static func notePanelSendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else { return }
        Self.keyDown(
            place: "panel",
            code: event.keyCode,
            timestamp: event.timestamp,
            dragActive: GridBackModel.shared.heldDrag.isActive
        )
    }

    /// The first move of a drag. Later moves in that drag print nothing.
    static func stackOnce() {
        guard !Self.didLogStack else { return }
        Self.didLogStack = true
        for frame in Self.stackFrames() {
            print("[#4] stack \(frame)")
        }
    }

    static func kind(of phase: HeldDrag.Phase) -> String {
        switch phase {
        case .idle:
            return "idle"
        case .grid:
            return "grid"
        case .insideFolder:
            return "inside folder"
        case .extracted:
            return "drag out of folder"
        case .inserting:
            return "inserting"
        }
    }

    private static func logTrustOnce() {
        guard !Self.didLogTrust else { return }
        Self.didLogTrust = true
        // Reads the current answer. Does not prompt.
        let answer = AXIsProcessTrusted() ? "yes" : "no"
        print("[#4] accessibility trusted=\(answer)")
    }

    private static func focus() -> String {
        let active = NSApp.isActive ? "yes" : "no"
        let panelKey = Self.overlayIsKey() ? "yes" : "no"
        return "active=\(active) key=\(Self.keyWindowLabel()) panelKey=\(panelKey)"
    }

    private static func keyWindowLabel() -> String {
        guard let identifier = NSApp.keyWindow?.identifier?.rawValue else { return "none" }
        if identifier == "GridBackOverlay" {
            return "GridBackOverlay"
        }
        return "other"
    }

    private static func overlayIsKey() -> Bool {
        for window in NSApp.windows where window.identifier?.rawValue == "GridBackOverlay" {
            if window.isKeyWindow {
                return true
            }
        }
        return false
    }

    /// Same clock as a key event. A mouse-up is the event in hand; anything else is not one.
    private static func mouseUpTimestamp() -> String {
        guard let event = NSApp.currentEvent else { return "none" }
        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return Self.stamp(event.timestamp)
        default:
            return "none"
        }
    }

    private static func stamp(_ time: TimeInterval) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), time)
    }

    private static func stackFrames() -> [String] {
        let specific = ["nextEvent", "NextEvent", "trackEvents", "runModal", "NSHostingView", "DragGesture"]
        let needles = specific + ["track", "mouse", "Gesture"]
        let rows: [(String, Bool)] = Thread.callStackSymbols.compactMap { raw in
            let frame = Self.stripPaths(raw)
            guard !frame.isEmpty, needles.contains(where: { frame.contains($0) }) else { return nil }
            return (frame, specific.contains(where: { frame.contains($0) }))
        }
        let must = rows.filter { $0.1 }
        if must.count >= 25 {
            return must.suffix(25).map { $0.0 }
        }
        var room = 25 - must.count
        var kept: [String] = []
        for row in rows.reversed() {
            if row.1 {
                kept.append(row.0)
            } else if room > 0 {
                kept.append(row.0)
                room -= 1
            }
        }
        return Array(kept.reversed())
    }

    /// Drops tokens that contain a path. Symbol names stay.
    private static func stripPaths(_ frame: String) -> String {
        frame.split(whereSeparator: \.isWhitespace)
            .filter { token in
                !token.contains("/") && !token.contains("\\") && !token.contains("~")
            }
            .joined(separator: " ")
    }
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

/// Fades the grid and the Dock backdrop together. The Dock itself is not in this group.
/// Both windows stay opaque; only their alpha moves, so the level and the black fill stay put.
enum OverlayFade {
    static func setAlpha(_ alpha: CGFloat, panel: NSWindow, backdrop: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.alphaValue = alpha
        backdrop.alphaValue = alpha
        CATransaction.commit()
    }

    /// Puts both windows on screen at alpha 0, before the fade-in starts.
    /// One disabled transaction, so a full-opacity frame cannot slip in between.
    static func orderFrontHidden(panel: NSWindow, backdrop: NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.alphaValue = 0
        backdrop.alphaValue = 0
        NSApp.unhide(nil)
        backdrop.orderFrontRegardless()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeKey()
        panel.alphaValue = 0
        backdrop.alphaValue = 0
        CATransaction.commit()
    }

    /// One animation group, so the two windows stay in step.
    /// A new group retargets an in-flight fade from the alpha on screen.
    static func animate(
        panel: NSWindow,
        backdrop: NSWindow,
        to alpha: CGFloat,
        duration: TimeInterval,
        curve: GridFade.Curve,
        completion: @escaping () -> Void
    ) {
        let timing = OverlayFade.timing(curve)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timing
            panel.animator().alphaValue = alpha
            backdrop.animator().alphaValue = alpha
        } completionHandler: {
            completion()
        }
    }

    /// Clicks pass through, and the panel gives up the keyboard, for the fade-out.
    static func releaseInteraction(on panel: NSWindow) {
        panel.ignoresMouseEvents = true
        panel.makeFirstResponder(nil)
        if panel.isKeyWindow {
            panel.resignKey()
        }
    }

    static func restoreInteraction(on panel: NSWindow) {
        panel.ignoresMouseEvents = false
    }

    private static func timing(_ curve: GridFade.Curve) -> CAMediaTimingFunction {
        switch curve {
        case .easeOut:
            return CAMediaTimingFunction(name: .easeOut)
        case .easeIn:
            return CAMediaTimingFunction(name: .easeIn)
        case .linear:
            return CAMediaTimingFunction(name: .linear)
        }
    }
}
