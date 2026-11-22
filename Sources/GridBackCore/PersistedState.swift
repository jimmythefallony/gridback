import Foundation

public struct PersistedState: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    /// Saved name of the list of places that have already been asked.
    public static let askedLocationsKey = "askedLocations"
    /// Saved name of the places whose wallpaper read was allowed.
    public static let grantedLocationsKey = "grantedLocations"

    public var version: Int
    public var layout: Layout
    public var shortcut: ShortcutChord
    public var askedLocations: [WallpaperPathPlace]
    public var grantedLocations: [WallpaperPathPlace]

    public init(
        version: Int = PersistedState.currentVersion,
        layout: Layout,
        shortcut: ShortcutChord,
        askedLocations: [WallpaperPathPlace] = [],
        grantedLocations: [WallpaperPathPlace] = []
    ) {
        self.version = version
        self.layout = layout
        self.shortcut = shortcut
        self.askedLocations = askedLocations
        self.grantedLocations = grantedLocations
    }

    public func repaired() -> PersistedState {
        let asked = FolderAccessRules.persisted(askedLocations)
        let allowed = Set(asked)
        return PersistedState(
            version: PersistedState.currentVersion,
            layout: LayoutEditor.repair(layout),
            shortcut: shortcut,
            askedLocations: asked,
            grantedLocations: FolderAccessRules.persisted(grantedLocations).filter { allowed.contains($0) }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case layout
        case shortcut
        case askedLocations
        case grantedLocations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        layout = try container.decode(Layout.self, forKey: .layout)
        shortcut = try container.decode(ShortcutChord.self, forKey: .shortcut)
        askedLocations = try Self.readPlaces(container, key: .askedLocations)
        grantedLocations = try Self.readPlaces(container, key: .grantedLocations)
    }

    /// A missing list, a null, or a value that is not a place name is ignored.
    private static func readPlaces(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> [WallpaperPathPlace] {
        guard container.contains(key) else { return [] }
        if try container.decodeNil(forKey: key) { return [] }
        let tokens = try container.decode([AskedLocationToken].self, forKey: key)
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
        try container.encode(grantedLocations, forKey: .grantedLocations)
    }
}

public enum PersistenceError: Error, Equatable {
    case unsupportedVersion(Int)
    case unreadable(String)
}
