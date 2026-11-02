import AppKit
import GridBackCore

enum ShortcutCapture {
    static func interpret(_ event: NSEvent) -> Result<ShortcutChord, ShortcutRejection> {
        let chord = ShortcutChord(
            keyCode: event.keyCode,
            carbonModifiers: carbonModifiers(from: event.modifierFlags),
            keyLabel: ShortcutFormatting.label(
                forKeyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers ?? ""
            )
        )
        if let rejection = chord.rejection() {
            return .failure(rejection)
        }
        return .success(chord)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= ShortcutChord.commandModifier }
        if flags.contains(.shift) { value |= ShortcutChord.shiftModifier }
        if flags.contains(.option) { value |= ShortcutChord.optionModifier }
        if flags.contains(.control) { value |= ShortcutChord.controlModifier }
        return value
    }
}

extension KeyModifiers {
    init(eventFlags flags: NSEvent.ModifierFlags) {
        var value: KeyModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        self = value
    }
}
