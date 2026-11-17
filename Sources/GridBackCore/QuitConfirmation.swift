import Foundation

/// Two presses of Command-Q quit. The first only arms a short confirmation.
///
/// The clock is whatever the caller passes in. A press while no GridBack window
/// is key does nothing, including leaving an existing arm alone.
public struct QuitConfirmation: Equatable, Sendable {
    /// How long the second press still counts, in seconds.
    public static let window: TimeInterval = 2
    /// ANSI Q.
    public static let quitKeyCode: UInt16 = 12

    public enum Decision: Equatable, Sendable {
        /// Not this chord, or no GridBack window is key. Leave the event alone.
        case pass
        /// A repeat of Command-Q while a GridBack window is key. Do not quit.
        case swallow
        /// First press. The confirmation is valid through `until`.
        case arm(until: TimeInterval)
        case quit
    }

    private var deadline: TimeInterval?

    public init() {}

    public mutating func decide(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        at now: TimeInterval,
        windowIsKey: Bool,
        isRepeat: Bool
    ) -> Decision {
        guard keyCode == Self.quitKeyCode, modifiers == .command else {
            return .pass
        }
        guard windowIsKey else {
            return .pass
        }
        if isRepeat {
            return .swallow
        }
        if let deadline, now <= deadline {
            self.deadline = nil
            return .quit
        }
        let until = now + Self.window
        deadline = until
        return .arm(until: until)
    }
}
