import Foundation

/// A global shortcut stored as a virtual key code plus Carbon modifier bits.
/// Carbon's `RegisterEventHotKey` is what the app uses to register it.
/// `keyLabel` is the text we show (from the keyboard that recorded it).
public struct ShortcutChord: Codable, Equatable, Sendable {
    public static let commandModifier: UInt32 = 256
    public static let shiftModifier: UInt32 = 512
    public static let optionModifier: UInt32 = 2048
    public static let controlModifier: UInt32 = 4096

    /// Virtual key codes that are modifiers themselves, not a shortcut key.
    public static let modifierOnlyKeyCodes: Set<UInt16> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63
    ]

    public var keyCode: UInt16
    public var carbonModifiers: UInt32
    public var keyLabel: String

    public init(keyCode: UInt16, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// Control-Option-G. Avoids the F4 key people associate with the old system grid.
    public static let `default` = ShortcutChord(
        keyCode: 5,
        carbonModifiers: controlModifier | optionModifier,
        keyLabel: "G"
    )

    public var hasRequiredModifier: Bool {
        let required = Self.commandModifier | Self.optionModifier | Self.controlModifier
        return carbonModifiers & required != 0
    }

    public var isModifierKeyOnly: Bool {
        Self.modifierOnlyKeyCodes.contains(keyCode)
    }

    public func rejection() -> ShortcutRejection? {
        if isModifierKeyOnly {
            return .modifierKeyOnly
        }
        if !hasRequiredModifier {
            return .needsModifier
        }
        return nil
    }

    public var displayString: String {
        ShortcutFormatting.display(modifiers: carbonModifiers, keyLabel: keyLabel)
    }
}

/// Why a key combination cannot be saved as the shortcut.
/// This is an `Error` because the recorder returns it from `Result`.
public enum ShortcutRejection: Error, Equatable, Sendable {
    case needsModifier
    case modifierKeyOnly
}

public enum ShortcutFormatting {
    public static func display(modifiers: UInt32, keyLabel: String) -> String {
        var text = ""
        if modifiers & ShortcutChord.controlModifier != 0 { text += "⌃" }
        if modifiers & ShortcutChord.optionModifier != 0 { text += "⌥" }
        if modifiers & ShortcutChord.shiftModifier != 0 { text += "⇧" }
        if modifiers & ShortcutChord.commandModifier != 0 { text += "⌘" }
        let label = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        text += label.isEmpty ? "?" : label
        return text
    }

    /// Prefer a stable name for keys that don't have a useful character.
    public static func label(forKeyCode keyCode: UInt16, characters: String) -> String {
        if let special = specialLabels[keyCode] {
            return special
        }
        if let text = SearchKeyRouting.searchableText(from: characters) {
            return text.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let specialLabels: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Esc",
        76: "Enter",
        117: "Delete",
        122: "F1",
        120: "F2",
        99: "F3",
        118: "F4",
        96: "F5",
        97: "F6",
        98: "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]
}
