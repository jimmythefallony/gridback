import Foundation

/// One on-screen window, reduced to what we need to recognize the system launcher.
public struct SystemLauncherWindow: Equatable, Sendable {
    public var owner: String
    public var name: String
    public var memoryBytes: Int
    public var width: Double
    public var height: Double

    public init(owner: String, name: String, memoryBytes: Int, width: Double, height: Double) {
        self.owner = owner
        self.name = name
        self.memoryBytes = memoryBytes
        self.width = width
        self.height = height
    }
}

/// Whether the system app grid (Launchpad / Apps) is showing.
///
/// The Dock always owns a full-screen host window of a few kilobytes. That
/// window is not the launcher. A visible launcher is a running Apps process,
/// a window named Launchpad, or a Dock window that actually holds a backing store.
public enum SystemLauncherVisibility {
    public static let launcherBundleID = "com.apple.apps.launcher"
    public static let dockBundleID = "com.apple.dock"
    /// Idle Dock host windows on this OS report about 2KB. A drawn launcher is far larger.
    public static let launcherBackingBytes = 500_000

    public static func isVisible(
        frontmostBundleID: String?,
        launcherProcessRunning: Bool,
        windows: [SystemLauncherWindow],
        screenWidth: Double,
        screenHeight: Double
    ) -> Bool {
        if launcherProcessRunning {
            return true
        }
        let front = frontmostBundleID ?? ""
        let dockIsFront = front == dockBundleID || front == launcherBundleID
        for window in windows {
            if window.name.range(of: "launchpad", options: .caseInsensitive) != nil {
                return true
            }
            if window.owner == "Apps" {
                return true
            }
            let coversScreen = window.width >= screenWidth * 0.75 && window.height >= screenHeight * 0.75
            let heavyDockSurface = coversScreen
                && window.memoryBytes >= launcherBackingBytes
                && (window.owner == "Dock" || window.owner == "Apps")
            if heavyDockSurface {
                return true
            }
            if coversScreen && dockIsFront && window.owner == "Dock" && !window.name.isEmpty {
                return true
            }
        }
        return false
    }
}
