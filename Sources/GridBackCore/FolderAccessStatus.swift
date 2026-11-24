import Foundation

/// Whether GridBack can read the current wallpaper's folder.
/// The place is a folder kind. A path is never part of this value.
public enum FolderAccessStatus: String, CaseIterable, Equatable, Sendable {
    /// Pictures, system files, other files, a disk inside the Mac, or iCloud Drive.
    case notNeeded
    /// A protected folder that has not been asked.
    case notAsked
    /// Asked, and neither allowed nor refused.
    case notNow
    /// Allowed, and the last read did not fail.
    case allowed
    /// Refused, or the last read failed.
    case notAllowed
    /// A network disk or a Photos library. GridBack does not read these.
    case unsupported

    /// `lastRead` is the latest deliberate read. A saved grant with no failed read counts as allowed.
    /// A denial wins over a grant. Photos libraries, network disks, and folders that need
    /// no permission ignore the saved flags.
    public static func make(
        place: WallpaperPathPlace,
        volumeKind: FolderVolumeKind,
        asked: Bool,
        granted: Bool,
        denied: Bool,
        lastRead: FolderReadResult
    ) -> FolderAccessStatus {
        if place == .photosLibrary || (place == .volumes && volumeKind == .network) {
            return .unsupported
        }
        if place == .pictures || place == .system || place == .other || place == .icloud
            || (place == .volumes && volumeKind == .fixed) {
            return .notNeeded
        }
        if denied || lastRead == .denied {
            return .notAllowed
        }
        if granted || lastRead == .granted {
            return .allowed
        }
        if asked {
            return .notNow
        }
        return .notAsked
    }

    /// A silent read can raise the system prompt on a folder that has not been decided.
    /// Only a folder that was already allowed or refused may be read with no question.
    public static func mayProbeSilently(_ status: FolderAccessStatus) -> Bool {
        switch status {
        case .allowed, .notAllowed:
            return true
        case .notNeeded, .notAsked, .notNow, .unsupported:
            return false
        }
    }
}

/// The button beside the Settings line. Not allowed has no second ask.
public enum FolderAccessAction: String, Equatable, Sendable {
    case allow
    case askAgain
    case openPrivacySettings
}

/// Words for the Settings line. Proposed copy lives here so the view does not invent a second set.
public enum FolderAccessStatusCopy {
    public static let rowTitle = "Wallpaper folder"
    public static let allowButton = "Allow…"
    public static let askAgainButton = "Ask again"
    public static let privacyButton = "Open Privacy Settings"
    public static let notAllowedDetail = "Turn on GridBack under Files & Folders, then come back."
    public static let hint = "Prefer not to give access? Copy the image to your Pictures folder and pick it again in System Settings > Wallpaper. GridBack can read it there without asking."

    public static func line(_ status: FolderAccessStatus) -> String {
        switch status {
        case .notNeeded:
            return "No permission needed"
        case .notAsked:
            return "Not asked yet"
        case .notNow:
            return "Not now"
        case .allowed:
            return "Allowed"
        case .notAllowed:
            return "Not allowed"
        case .unsupported:
            return "GridBack doesn't read wallpapers from here"
        }
    }

    /// Where the picture sits, as a folder kind. Nil when there is no picture file.
    public static func placePhrase(_ place: WallpaperPathPlace, volumeKind: FolderVolumeKind) -> String {
        switch place {
        case .desktop:
            return "On your Desktop"
        case .documents:
            return "In your Documents folder"
        case .downloads:
            return "In your Downloads folder"
        case .pictures:
            return "In your Pictures folder"
        case .icloud:
            return "In iCloud Drive"
        case .photosLibrary:
            return "In your Photos library"
        case .system:
            return "In a system folder"
        case .other:
            return "In another folder"
        case .volumes:
            switch volumeKind {
            case .network:
                return "On a network disk"
            case .removable:
                return "On an external disk"
            case .fixed:
                return "On this Mac"
            case .none:
                return "On a disk"
            }
        }
    }

    public static func detail(_ status: FolderAccessStatus) -> String? {
        status == .notAllowed ? notAllowedDetail : nil
    }

    public static func hint(for status: FolderAccessStatus) -> String? {
        switch status {
        case .notNow, .notAllowed:
            return hint
        case .notNeeded, .notAsked, .allowed, .unsupported:
            return nil
        }
    }

    /// Not allowed opens Privacy settings. It does not ask again.
    public static func action(_ status: FolderAccessStatus) -> FolderAccessAction? {
        switch status {
        case .notAsked:
            return .allow
        case .notNow:
            return .askAgain
        case .allowed, .notAllowed:
            return .openPrivacySettings
        case .notNeeded, .unsupported:
            return nil
        }
    }

    public static func buttonTitle(_ action: FolderAccessAction) -> String {
        switch action {
        case .allow:
            return allowButton
        case .askAgain:
            return askAgainButton
        case .openPrivacySettings:
            return privacyButton
        }
    }
}

/// The picture the Settings line is about. Built from path text the caller already has.
public struct FolderAccessPicture: Equatable, Sendable {
    public var path: String
    public var place: WallpaperPathPlace

    public init(path: String, place: WallpaperPathPlace) {
        self.path = path
        self.place = place
    }
}

public enum FolderAccessTarget {
    /// A colour or an Aerial has no picture file, so the line needs no permission.
    /// A folder of pictures uses the current frame when the caller has one.
    /// This does not open the file.
    public static func picture(
        provider: String?,
        isFolder: Bool,
        storePaths: [String],
        workspacePath: String?
    ) -> FolderAccessPicture? {
        if provider == WallpaperStoreIndex.colorProvider || provider == WallpaperStoreIndex.aerialsProvider {
            return nil
        }
        if isFolder, let path = normalizedPicture(workspacePath) {
            return FolderAccessPicture(path: path, place: WallpaperPathPlace.classify(path))
        }
        for raw in storePaths {
            if let path = normalizedPicture(raw) {
                return FolderAccessPicture(path: path, place: WallpaperPathPlace.classify(path))
            }
        }
        guard let path = normalizedPicture(workspacePath) else { return nil }
        return FolderAccessPicture(path: path, place: WallpaperPathPlace.classify(path))
    }

    private static func normalizedPicture(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let path = WallpaperPathPlace.normalized(raw)
        guard path != "/" else { return nil }
        return path
    }
}

/// The three saved lists, in the order they are written.
public struct FolderAccessLists: Equatable, Sendable {
    public var asked: [WallpaperPathPlace]
    public var granted: [WallpaperPathPlace]
    public var denied: [WallpaperPathPlace]

    public init(
        asked: [WallpaperPathPlace],
        granted: [WallpaperPathPlace],
        denied: [WallpaperPathPlace]
    ) {
        self.asked = asked
        self.granted = granted
        self.denied = denied
    }
}

public enum FolderAccessEdits {
    /// Ask again applies only to Not now. The place is removed from the asked list.
    /// Not allowed is returned unchanged, so a refusal is not asked a second time.
    public static func askAgain(
        place: WallpaperPathPlace,
        volumeKind: FolderVolumeKind,
        asked: [WallpaperPathPlace],
        granted: [WallpaperPathPlace],
        denied: [WallpaperPathPlace],
        lastRead: FolderReadResult
    ) -> FolderAccessLists {
        let status = FolderAccessStatus.make(
            place: place,
            volumeKind: volumeKind,
            asked: asked.contains(place),
            granted: granted.contains(place),
            denied: denied.contains(place),
            lastRead: lastRead
        )
        guard status == .notNow else {
            return FolderAccessLists(asked: asked, granted: granted, denied: denied)
        }
        return FolderAccessLists(
            asked: FolderAccessRules.persisted(asked.filter { $0 != place }),
            granted: FolderAccessRules.persisted(granted),
            denied: FolderAccessRules.persisted(denied)
        )
    }

    /// A successful quiet read moves the place from denied to granted and drops that file
    /// from the denial cache. A failed read records the refusal.
    public static func recheck(
        succeeded: Bool,
        place: WallpaperPathPlace,
        path: String,
        modified: Date?,
        asked: [WallpaperPathPlace],
        granted: [WallpaperPathPlace],
        denied: [WallpaperPathPlace],
        denial: FolderDenialCache
    ) -> (lists: FolderAccessLists, denial: FolderDenialCache) {
        var asked = asked
        var granted = granted
        var denied = denied
        var denial = denial
        if succeeded {
            denial.clear(path: path)
            denied.removeAll { $0 == place }
            if FolderAccessRules.askable.contains(place) {
                if !asked.contains(place) {
                    asked.append(place)
                }
                if !granted.contains(place) {
                    granted.append(place)
                }
            }
        } else if FolderAccessRules.askable.contains(place) {
            denial.store(path: path, modified: modified)
            granted.removeAll { $0 == place }
            if !denied.contains(place) {
                denied.append(place)
            }
        }
        let askedList = FolderAccessRules.persisted(asked)
        let allowed = Set(askedList)
        return (
            FolderAccessLists(
                asked: askedList,
                granted: FolderAccessRules.persisted(granted).filter { allowed.contains($0) },
                denied: FolderAccessRules.persisted(denied)
            ),
            denial
        )
    }
}
