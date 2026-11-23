import Foundation

/// Which places may be asked, and which reads must not download a file.
/// Edit the lists here. Callers should not keep a second copy.
public enum FolderAccessRules {
    /// Protected places that may be offered an ask.
    /// Photos libraries are left out. Network volumes are left out separately.
    /// Pictures and system files are not protected, so they are read without an ask.
    public static let askable: Set<WallpaperPathPlace> = [
        .desktop, .documents, .downloads, .icloud, .volumes
    ]

    /// Network volumes are never offered an ask and never read.
    /// An unknown kind follows the volumes place, which may be asked.
    public static let neverAskVolumeKinds: Set<FolderVolumeKind> = [.network]

    /// Places whose files must not be downloaded in order to read them.
    public static let neverDownload: Set<WallpaperPathPlace> = [.icloud]

    public static func allowsDownload(_ place: WallpaperPathPlace) -> Bool {
        !neverDownload.contains(place)
    }

    /// Askable places only, each once, in a stable order.
    public static func persisted(_ places: [WallpaperPathPlace]) -> [WallpaperPathPlace] {
        Set(places.filter { askable.contains($0) }).sorted { $0.rawValue < $1.rawValue }
    }
}

/// Path text cannot tell a removable disk from a network volume, so the caller passes the kind.
public enum FolderVolumeKind: String, Equatable, Sendable {
    case none
    case removable
    /// A local volume that is not removable. macOS does not ask before it is read.
    case fixed
    case network
}

/// The last deliberate read of one wallpaper path.
public enum FolderReadResult: String, Equatable, Sendable {
    case granted
    case denied
    case unknown
}

/// What to do with a wallpaper place. Offering an ask does not touch the file.
public enum FolderAccessDecision: String, Equatable, Sendable {
    case doNotTouch
    case tryRead
    case fallback
    case offerAsk
}

public enum FolderAccessPolicy {
    /// An unasked protected place is never a read. A denial or a Not now does not ask again.
    public static func decide(
        place: WallpaperPathPlace,
        askedLocations: Set<WallpaperPathPlace>,
        lastRead: FolderReadResult,
        volumeKind: FolderVolumeKind = .none
    ) -> FolderAccessDecision {
        if place == .volumes, FolderAccessRules.neverAskVolumeKinds.contains(volumeKind) {
            return .doNotTouch
        }
        if place == .volumes, volumeKind == .fixed {
            return lastRead == .denied ? .fallback : .tryRead
        }
        if !place.isProtected {
            return lastRead == .denied ? .fallback : .tryRead
        }
        if !FolderAccessRules.askable.contains(place) {
            return .doNotTouch
        }
        if !askedLocations.contains(place) {
            return .offerAsk
        }
        switch lastRead {
        case .granted:
            return .tryRead
        case .denied, .unknown:
            return .fallback
        }
    }

    /// A cached denial blocks a read until it is time to try again.
    /// Not now stays a fallback, and an excluded place stays untouched.
    public static func applying(
        _ decision: FolderAccessDecision,
        lastRead: FolderReadResult,
        shouldRetryDenied: Bool
    ) -> FolderAccessDecision {
        guard lastRead == .denied else { return decision }
        if shouldRetryDenied {
            return decision == .fallback ? .tryRead : decision
        }
        return decision == .tryRead ? .fallback : decision
    }
}

/// An ask may be offered only when the grid is closed and no drag is active.
public enum FolderAskTiming {
    public static func mayOffer(gridClosed: Bool, dragActive: Bool) -> Bool {
        gridClosed && !dragActive
    }
}

/// A line for the log. The place name is the only location it carries.
public enum FolderAccessLog {
    public static func line(place: WallpaperPathPlace, decision: FolderAccessDecision) -> String {
        "place=\(place.rawValue) decision=\(decision.rawValue)"
    }
}

/// Denied reads, remembered per path and modification date.
/// A denial is tried again only when the wallpaper changes or the app becomes active.
/// Wallpaper change means a different path or a different modification date.
public struct FolderDenialCache: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var path: String
        public var modified: Date?

        public init(path: String, modified: Date?) {
            self.path = path
            self.modified = modified
        }
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public mutating func store(path: String, modified: Date?) {
        entries.removeAll { $0.path == path }
        entries.append(Entry(path: path, modified: modified))
    }

    /// True only when a stored denial should be read again.
    /// An empty cache has nothing to retry. A stored denial for another path is a wallpaper change.
    public func shouldRetry(path: String, modified: Date?, appBecameActive: Bool) -> Bool {
        guard let entry = entries.first(where: { $0.path == path }) else {
            return !entries.isEmpty
        }
        if appBecameActive { return true }
        return entry.modified != modified
    }
}

/// Operations that would touch a wallpaper file.
public protocol FolderFileAccessor {
    func fileExists(at path: String, allowingDownload: Bool)
    func stat(at path: String, allowingDownload: Bool)
    func resourceValues(at path: String, allowingDownload: Bool)
    func list(at path: String, allowingDownload: Bool)
    func readImage(at path: String, allowingDownload: Bool)
}

/// Runs those operations only when the decision is `tryRead`.
/// A protected place that has not been asked never reaches the accessor.
public enum FolderFileAttempt {
    public static func perform<Accessor: FolderFileAccessor>(
        path: String,
        askedLocations: Set<WallpaperPathPlace>,
        lastRead: FolderReadResult,
        volumeKind: FolderVolumeKind = .none,
        denial: FolderDenialCache = FolderDenialCache(),
        modified: Date? = nil,
        appBecameActive: Bool = false,
        accessor: Accessor
    ) -> FolderAccessDecision {
        let place = WallpaperPathPlace.classify(path)
        let base = FolderAccessPolicy.decide(
            place: place,
            askedLocations: askedLocations,
            lastRead: lastRead,
            volumeKind: volumeKind
        )
        let decision = FolderAccessPolicy.applying(
            base,
            lastRead: lastRead,
            shouldRetryDenied: denial.shouldRetry(
                path: path,
                modified: modified,
                appBecameActive: appBecameActive
            )
        )
        guard decision == .tryRead else { return decision }
        let download = FolderAccessRules.allowsDownload(place)
        accessor.fileExists(at: path, allowingDownload: download)
        accessor.stat(at: path, allowingDownload: download)
        accessor.resourceValues(at: path, allowingDownload: download)
        accessor.list(at: path, allowingDownload: download)
        accessor.readImage(at: path, allowingDownload: download)
        return decision
    }
}
