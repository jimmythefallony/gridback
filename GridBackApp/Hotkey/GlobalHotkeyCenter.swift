import Carbon
import Foundation
import GridBackCore
import os

/// Registers one system-wide shortcut with Carbon `RegisterEventHotKey`.
///
/// That API consumes the keystroke, so the front app does not also see it, and
/// it does not ask for Accessibility access. The call is old, but it is still
/// the mechanism menu-bar apps use for a configurable shortcut. If registration
/// fails, the status code is returned and the menu bar item explains that the
/// shortcut is unavailable. Open and Quit keep working from the menu.
final class GlobalHotkeyCenter {
    private let signature: FourCharCode = 0x4744424B // GDBK
    private let hotKeyID = UInt32(1)
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let target = HotKeyTarget()
    private let log = Logger(subsystem: "com.jimmythefallony.GridBack", category: "hotkey")

    func register(_ chord: ShortcutChord, onPress: @escaping () -> Void) -> OSStatus {
        target.onPress = onPress
        if handler == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let installed = InstallEventHandler(
                GetApplicationEventTarget(),
                gridBackHotKeyCallback,
                1,
                &spec,
                Unmanaged.passUnretained(target).toOpaque(),
                &handler
            )
            if installed != noErr {
                log.error("InstallEventHandler failed: \(Int(installed), privacy: .public)")
                return installed
            }
        }

        unregisterHotKeyOnly()
        let identity = EventHotKeyID(signature: signature, id: hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode),
            chord.carbonModifiers,
            identity,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        if status != noErr {
            log.error("RegisterEventHotKey failed: \(Int(status), privacy: .public)")
            hotKey = nil
        }
        return status
    }

    func unregister() {
        unregisterHotKeyOnly()
    }

    private func unregisterHotKeyOnly() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    deinit {
        unregisterHotKeyOnly()
        if let handler {
            RemoveEventHandler(handler)
        }
    }
}

private final class HotKeyTarget {
    var onPress: () -> Void = {}
}

private func gridBackHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let target = Unmanaged<HotKeyTarget>.fromOpaque(userData).takeUnretainedValue()
    var identity = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        // Swift imports Carbon's ByteCount parameter as Int.
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identity
    )
    guard status == noErr else { return status }
    DispatchQueue.main.async {
        target.onPress()
    }
    return noErr
}
