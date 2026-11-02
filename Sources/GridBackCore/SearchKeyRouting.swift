import Foundation

public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)

    public var isCommandChord: Bool {
        contains(.command) || contains(.option) || contains(.control)
    }
}

public enum SearchKeyAction: Equatable, Sendable {
    case startOrAppend(String)
    case backspace
    case clearSearch
    case dismiss
    case launchSelected
    case moveSelection(delta: Int)
    case changePage(delta: Int)
    case ignored
}

/// Keyboard behavior while the overlay is key.
/// Escape clears a search query first and dismisses only when the query is empty.
/// Typing starts a search. Return launches the selected result while searching.
public enum SearchKeyRouting {
    public static let escapeKeyCode: UInt16 = 53
    public static let returnKeyCode: UInt16 = 36
    public static let keypadEnterKeyCode: UInt16 = 76
    public static let deleteKeyCode: UInt16 = 51
    public static let forwardDeleteKeyCode: UInt16 = 117
    public static let leftArrowKeyCode: UInt16 = 123
    public static let rightArrowKeyCode: UInt16 = 124
    public static let downArrowKeyCode: UInt16 = 125
    public static let upArrowKeyCode: UInt16 = 126

    public static func action(
        keyCode: UInt16,
        characters: String,
        modifiers: KeyModifiers,
        isSearching: Bool,
        columns: Int
    ) -> SearchKeyAction {
        if keyCode == escapeKeyCode && !modifiers.isCommandChord {
            return isSearching ? .clearSearch : .dismiss
        }
        if modifiers.isCommandChord {
            return .ignored
        }
        if keyCode == returnKeyCode || keyCode == keypadEnterKeyCode {
            return isSearching ? .launchSelected : .ignored
        }
        if keyCode == deleteKeyCode || keyCode == forwardDeleteKeyCode {
            return isSearching ? .backspace : .ignored
        }
        let stride = max(columns, 1)
        if keyCode == leftArrowKeyCode {
            return isSearching ? .moveSelection(delta: -1) : .changePage(delta: -1)
        }
        if keyCode == rightArrowKeyCode {
            return isSearching ? .moveSelection(delta: 1) : .changePage(delta: 1)
        }
        if keyCode == upArrowKeyCode {
            return isSearching ? .moveSelection(delta: -stride) : .ignored
        }
        if keyCode == downArrowKeyCode {
            return isSearching ? .moveSelection(delta: stride) : .ignored
        }
        guard let text = searchableText(from: characters) else {
            return .ignored
        }
        return .startOrAppend(text)
    }

    /// Text that can be added to the query. Control characters and function-key
    /// sentinels are rejected so arrows do not show up as glyphs.
    public static func searchableText(from characters: String) -> String? {
        guard !characters.isEmpty else { return nil }
        for scalar in characters.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F {
                return nil
            }
            if (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            }
        }
        return characters
    }
}
