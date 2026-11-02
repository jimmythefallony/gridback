import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var layout: Layout
    public var shortcut: ShortcutChord

    public init(version: Int = PersistedState.currentVersion, layout: Layout, shortcut: ShortcutChord) {
        self.version = version
        self.layout = layout
        self.shortcut = shortcut
    }

    public func repaired() -> PersistedState {
        PersistedState(
            version: version,
            layout: LayoutEditor.repair(layout),
            shortcut: shortcut
        )
    }
}

public enum PersistenceError: Error, Equatable {
    case unsupportedVersion(Int)
    case unreadable(String)
}
