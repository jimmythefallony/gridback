import Foundation

/// How the grid fades, and how the icon page zooms, when it opens and closes.
///
/// Open takes a quarter second and eases out. The wallpaper fades in, and the
/// icon page follows a moment later, shrinking from a little larger than rest.
/// Close is quicker and eases in: the page grows back and fades out with the
/// wallpaper, with no delay. Reduce Motion drops the zoom and uses one short
/// cross-fade. There is no spring.
///
/// The windows stay up while a close is playing. A show during that close
/// reverses, and the close's completion is ignored. A hide during the open
/// does the same in the other direction. A second hide while a close is
/// already playing does nothing.
public struct GridFade: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        case opening
        case open
        case closing
    }

    public enum Curve: Equatable, Sendable {
        case easeOut
        case easeIn
        case linear
    }

    /// One step the windows and the icon page should play.
    public struct Transition: Equatable, Sendable {
        public var phase: Phase
        public var generation: Int
        /// Window alpha this step moves toward.
        public var alpha: Double
        public var duration: Double
        public var curve: Curve
        /// 1.08 when the icon page zooms, 1 when it stays still.
        public var iconScale: Double
        public var scalesIcons: Bool
        /// False for Reduce Motion. The window alpha is the whole cross-fade then.
        public var fadesIcons: Bool
        /// Opacity the icon page moves toward when `fadesIcons` is true.
        public var iconOpacity: Double
        public var iconDelay: Double
        public var iconDuration: Double
        /// A fresh open starts from the enlarged, hidden page. A reverse keeps the scale already on screen.
        public var fresh: Bool
    }

    public static let openDuration = 0.25
    public static let closeDuration = 0.18
    public static let reducedDuration = 0.15
    public static let iconScale = 1.08
    public static let iconDelay = 0.03

    public private(set) var phase: Phase
    public private(set) var generation: Int

    public init() {
        phase = .closed
        generation = 0
    }

    /// Start an open, or reverse a close that is still on screen.
    /// A show that is already opening or open does nothing.
    public mutating func show(reduceMotion: Bool) -> Transition? {
        switch phase {
        case .closed:
            return beginOpen(reduceMotion: reduceMotion, fresh: true)
        case .closing:
            return beginOpen(reduceMotion: reduceMotion, fresh: false)
        case .opening, .open:
            return nil
        }
    }

    /// Start a close, or reverse an open that has not finished.
    /// A hide while a close is already playing, or while nothing is open, does nothing.
    public mutating func hide(reduceMotion: Bool) -> Transition? {
        switch phase {
        case .opening, .open:
            return beginClose(reduceMotion: reduceMotion)
        case .closing, .closed:
            return nil
        }
    }

    /// The animation for `generation` finished.
    /// A generation from an interrupted open or close does nothing.
    public mutating func complete(generation: Int) -> Phase? {
        guard generation == self.generation else { return nil }
        switch phase {
        case .opening:
            phase = .open
            return .open
        case .closing:
            phase = .closed
            return .closed
        case .open, .closed:
            return nil
        }
    }

    public static func windowDuration(opening: Bool, reduceMotion: Bool) -> Double {
        if reduceMotion { return reducedDuration }
        return opening ? openDuration : closeDuration
    }

    public static func delay(fresh: Bool, reduceMotion: Bool) -> Double {
        if reduceMotion || !fresh { return 0 }
        return iconDelay
    }

    /// The icon page finishes with the wallpaper. On a fresh open it waits out the lead-in first.
    public static func iconDuration(opening: Bool, fresh: Bool, reduceMotion: Bool) -> Double {
        if reduceMotion { return reducedDuration }
        if opening && fresh { return openDuration - iconDelay }
        return opening ? openDuration : closeDuration
    }

    public static func presentedIconScale(reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : iconScale
    }

    public static func curve(opening: Bool, reduceMotion: Bool) -> Curve {
        if reduceMotion { return .linear }
        return opening ? .easeOut : .easeIn
    }

    private mutating func beginOpen(reduceMotion: Bool, fresh: Bool) -> Transition {
        generation += 1
        phase = .opening
        return Transition(
            phase: .opening,
            generation: generation,
            alpha: 1,
            duration: Self.windowDuration(opening: true, reduceMotion: reduceMotion),
            curve: Self.curve(opening: true, reduceMotion: reduceMotion),
            iconScale: Self.presentedIconScale(reduceMotion: reduceMotion),
            scalesIcons: !reduceMotion,
            fadesIcons: !reduceMotion,
            iconOpacity: 1,
            iconDelay: Self.delay(fresh: fresh, reduceMotion: reduceMotion),
            iconDuration: Self.iconDuration(opening: true, fresh: fresh, reduceMotion: reduceMotion),
            fresh: fresh
        )
    }

    private mutating func beginClose(reduceMotion: Bool) -> Transition {
        generation += 1
        phase = .closing
        return Transition(
            phase: .closing,
            generation: generation,
            alpha: 0,
            duration: Self.windowDuration(opening: false, reduceMotion: reduceMotion),
            curve: Self.curve(opening: false, reduceMotion: reduceMotion),
            iconScale: Self.presentedIconScale(reduceMotion: reduceMotion),
            scalesIcons: !reduceMotion,
            fadesIcons: !reduceMotion,
            iconOpacity: reduceMotion ? 1 : 0,
            iconDelay: 0,
            iconDuration: Self.iconDuration(opening: false, fresh: false, reduceMotion: reduceMotion),
            fresh: false
        )
    }
}
