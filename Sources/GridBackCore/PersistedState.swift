import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    /// Saved name of the list of places that have already been asked.
    public static let askedLocationsKey = "askedLocations"

    public var version: Int
    public var layout: Layout
    public var shortcut: ShortcutChord
    public var askedLocations: [WallpaperPathPlace]

    public init(
        version: Int = PersistedState.currentVersion,
        layout: Layout,
        shortcut: ShortcutChord,
        askedLocations: [WallpaperPathPlace] = []
    ) {
        self.version = version
        self.layout = layout
        self.shortcut = shortcut
        self.askedLocations = askedLocations
    }

    public func repaired() -> PersistedState {
        PersistedState(
            version: PersistedState.currentVersion,
            layout: LayoutEditor.repair(layout),
            shortcut: shortcut,
            askedLocations: FolderAccessRules.persisted(askedLocations)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case layout
        case shortcut
        case askedLocations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        layout = try container.decode(Layout.self, forKey: .layout)
        shortcut = try container.decode(ShortcutChord.self, forKey: .shortcut)
        askedLocations = try Self.readAskedLocations(container)
    }

    /// A missing list, a null, or a value that is not a place name is ignored.
    private static func readAskedLocations(
        _ container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [WallpaperPathPlace] {
        guard container.contains(.askedLocations) else { return [] }
        if try container.decodeNil(forKey: .askedLocations) { return [] }
        let tokens = try container.decode([AskedLocationToken].self, forKey: .askedLocations)
        return tokens.compactMap { $0.name.flatMap(WallpaperPathPlace.init(rawValue:)) }
    }

    private struct AskedLocationToken: Decodable {
        var name: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                name = nil
                return
            }
            if let text = try? container.decode(String.self) {
                name = text
                return
            }
            name = nil
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            if (try? container.decode([AskedLocationToken].self)) != nil { return }
            if (try? container.decode([String: AskedLocationToken].self)) != nil { return }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "asked location")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(layout, forKey: .layout)
        try container.encode(shortcut, forKey: .shortcut)
        try container.encode(askedLocations, forKey: .askedLocations)
    }
}

public enum PersistenceError: Error, Equatable {
    case unsupportedVersion(Int)
    case unreadable(String)
}
