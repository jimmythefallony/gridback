import AppKit

/// The display macOS treats as primary: Quartz's main display, whose origin is
/// (0, 0). That is the display the menu bar is arranged on, including when
/// mirroring is on.
///
/// `NSScreen.main` is not this. It is the screen that holds the key window, so
/// it follows keyboard focus instead of the configured primary display.
enum PrimaryDisplay {
    static func screen() -> NSScreen? {
        let primaryID = CGMainDisplayID()
        if let match = NSScreen.screens.first(where: { displayID(of: $0) == primaryID }) {
            return match
        }
        return NSScreen.screens.first
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
