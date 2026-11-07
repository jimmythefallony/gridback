import Foundation

/// One tile on the grid. A folder holds apps and cannot contain another folder.
public enum GridItem: Codable, Equatable, Sendable, Identifiable, ExpressibleByStringLiteral {
    case app(String)
    case folder(String)

    public var id: String {
        switch self {
        case .app(let id), .folder(let id):
            return id
        }
    }

    public init(stringLiteral value: String) {
        self = .app(value)
    }

    public var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    private enum FolderKey: String, CodingKey {
        case folder
    }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: FolderKey.self),
           let id = try keyed.decodeIfPresent(String.self, forKey: .folder) {
            self = .folder(id)
            return
        }
        let id = try decoder.singleValueContainer().decode(String.self)
        self = .app(id)
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .app(let id):
            var container = encoder.singleValueContainer()
            try container.encode(id)
        case .folder(let id):
            var container = encoder.container(keyedBy: FolderKey.self)
            try container.encode(id, forKey: .folder)
        }
    }
}

public struct AppFolder: Codable, Equatable, Sendable, Identifiable {
    public static let defaultName = "Folder"

    public var id: String
    public var name: String
    public var appIDs: [String]

    public init(id: String, name: String, appIDs: [String]) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }

    public static func newID() -> String {
        "folder.\(UUID().uuidString)"
    }
}

/// Pages of tiles. A page never borrows icons from the next page to fill
/// itself, so a short page can sit in front of a later page.
public struct Layout: Equatable, Sendable {
    public var pages: [[GridItem]]
    public var folders: [AppFolder]
    public var metrics: GridMetrics

    public init(pages: [[GridItem]], folders: [AppFolder] = [], metrics: GridMetrics) {
        self.pages = pages
        self.folders = folders
        self.metrics = metrics
    }

    /// A layout of loose apps, which is how version 1 saved files are shaped.
    public init(pages: [[String]], metrics: GridMetrics) {
        self.init(pages: pages.map { $0.map(GridItem.app) }, metrics: metrics)
    }

    public func indexPath(of id: String) -> (page: Int, slot: Int)? {
        for (pageIndex, page) in pages.enumerated() {
            if let slot = page.firstIndex(where: { $0.id == id }) {
                return (pageIndex, slot)
            }
        }
        return nil
    }

    public func folder(_ id: String) -> AppFolder? {
        folders.first { $0.id == id }
    }

    /// Apps in reading order, including the apps inside each folder.
    public var orderedIDs: [String] {
        var ids: [String] = []
        for page in pages {
            for item in page {
                switch item {
                case .app(let id):
                    ids.append(id)
                case .folder(let id):
                    if let folder = folder(id) {
                        ids.append(contentsOf: folder.appIDs)
                    }
                }
            }
        }
        return ids
    }
}

extension Layout: Codable {
    private enum CodingKeys: String, CodingKey {
        case pages, folders, metrics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pages = try container.decode([[GridItem]].self, forKey: .pages)
        folders = try container.decodeIfPresent([AppFolder].self, forKey: .folders) ?? []
        metrics = try container.decode(GridMetrics.self, forKey: .metrics)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
        try container.encode(folders, forKey: .folders)
        try container.encode(metrics, forKey: .metrics)
    }
}
