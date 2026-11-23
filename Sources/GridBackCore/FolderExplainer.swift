import Foundation

/// What the explainer should do right now. Waiting keeps the offer unanswered.
public enum FolderExplainerStep: Equatable, Sendable {
    case idle
    case show(WallpaperPathPlace)
    case wait(WallpaperPathPlace)
}

/// The places to save after Allow or Not now. Allow is the only reply that reads the file.
public struct FolderExplainerRecord: Equatable, Sendable {
    public var place: WallpaperPathPlace
    public var asked: [WallpaperPathPlace]
    public var granted: [WallpaperPathPlace]
    public var readAfter: Bool

    public init(
        place: WallpaperPathPlace,
        asked: [WallpaperPathPlace],
        granted: [WallpaperPathPlace],
        readAfter: Bool
    ) {
        self.place = place
        self.asked = asked
        self.granted = granted
        self.readAfter = readAfter
    }
}

/// One offer of the folder explainer.
/// The place is recorded only when the person answers. Opening the grid hides the offer and keeps it.
public struct FolderExplainerSession: Equatable, Sendable {
    public private(set) var asked: Set<WallpaperPathPlace>
    public private(set) var granted: Set<WallpaperPathPlace>
    /// A place that has been offered and not answered. Hidden while the grid is open or a drag is active.
    public private(set) var pending: WallpaperPathPlace?
    public private(set) var visible: Bool

    public init(asked: [WallpaperPathPlace] = [], granted: [WallpaperPathPlace] = []) {
        let askedList = FolderAccessRules.persisted(asked)
        let allowed = Set(askedList)
        self.asked = allowed
        self.granted = Set(FolderAccessRules.persisted(granted).filter { allowed.contains($0) })
        self.pending = nil
        self.visible = false
    }

    public var askedList: [WallpaperPathPlace] {
        FolderAccessRules.persisted(Array(asked))
    }

    public var grantedList: [WallpaperPathPlace] {
        FolderAccessRules.persisted(Array(granted))
    }

    public func lastRead(for place: WallpaperPathPlace) -> FolderReadResult {
        granted.contains(place) ? .granted : .unknown
    }

    /// Look at the wallpaper that is current. This does not open the file.
    public mutating func note(
        place: WallpaperPathPlace,
        volumeKind: FolderVolumeKind = .none,
        gridClosed: Bool,
        dragActive: Bool
    ) -> FolderExplainerStep {
        let decision = FolderAccessPolicy.decide(
            place: place,
            askedLocations: asked,
            lastRead: lastRead(for: place),
            volumeKind: volumeKind
        )
        guard decision == .offerAsk else {
            pending = nil
            visible = false
            return .idle
        }
        pending = place
        return present(place, gridClosed: gridClosed, dragActive: dragActive)
    }

    /// The grid opened. A visible offer is hidden and stays unanswered.
    public mutating func gridOpened() -> FolderExplainerStep {
        guard let pending else {
            visible = false
            return .idle
        }
        visible = false
        return .wait(pending)
    }

    /// The grid closed. A pending offer is shown when no drag is active.
    public mutating func gridClosed(dragActive: Bool) -> FolderExplainerStep {
        guard let pending else {
            visible = false
            return .idle
        }
        return present(pending, gridClosed: true, dragActive: dragActive)
    }

    /// A drag ended. The offer stays hidden while the grid is open.
    public mutating func dragEnded(gridClosed: Bool) -> FolderExplainerStep {
        guard let pending else {
            visible = false
            return .idle
        }
        return present(pending, gridClosed: gridClosed, dragActive: false)
    }

    /// The wallpaper is no longer one that can be asked. The offer is dropped and not recorded.
    public mutating func clearUnanswered() -> FolderExplainerStep {
        pending = nil
        visible = false
        return .idle
    }

    public mutating func allow() -> FolderExplainerRecord? {
        answer(readAfter: true)
    }

    public mutating func notNow() -> FolderExplainerRecord? {
        answer(readAfter: false)
    }

    /// A deliberate read was allowed. Ignored unless this place was already asked.
    public mutating func noteGranted(_ place: WallpaperPathPlace) {
        guard asked.contains(place), FolderAccessRules.askable.contains(place) else { return }
        granted.insert(place)
        granted = Set(grantedList)
    }

    /// A deliberate read was refused. The place stays asked and is not read again.
    public mutating func noteDenied(_ place: WallpaperPathPlace) {
        granted.remove(place)
    }

    private mutating func present(
        _ place: WallpaperPathPlace,
        gridClosed: Bool,
        dragActive: Bool
    ) -> FolderExplainerStep {
        if FolderAskTiming.mayOffer(gridClosed: gridClosed, dragActive: dragActive) {
            visible = true
            return .show(place)
        }
        visible = false
        return .wait(place)
    }

    private mutating func answer(readAfter: Bool) -> FolderExplainerRecord? {
        guard let place = pending, FolderAccessRules.askable.contains(place) else { return nil }
        asked.insert(place)
        if !readAfter {
            granted.remove(place)
        }
        pending = nil
        visible = false
        return FolderExplainerRecord(
            place: place,
            asked: askedList,
            granted: grantedList,
            readAfter: readAfter
        )
    }
}

/// The explainer's size. The width stays fixed so a second show cannot collapse to one word per line.
public struct FolderExplainerSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum FolderExplainerLayout {
    public static let width = 440.0
    public static let minimumHeight = 128.0
    public static let maximumHeight = 280.0

    /// `measuredWidth` and `measuredHeight` come from laying the text out at `width`.
    /// A narrower measurement is the collapsed show, so its height is not used.
    public static func size(measuredWidth: Double, measuredHeight: Double) -> FolderExplainerSize {
        let measuredAtContentWidth = measuredWidth >= width * 0.75 && measuredHeight.isFinite && measuredHeight > 0
        let raw = measuredAtContentWidth ? measuredHeight : minimumHeight
        let height = min(max(raw, minimumHeight), maximumHeight)
        return FolderExplainerSize(width: width, height: height)
    }
}

/// A shortcut that arrives while the system folder prompt is waiting.
/// Queuing it would open the grid after the prompt closes, so it is dropped.
public enum FolderPromptHotkey {
    public enum Action: Equatable, Sendable {
        case perform
        case drop
    }

    public static func action(systemPromptWaiting: Bool) -> Action {
        systemPromptWaiting ? .drop : .perform
    }
}

/// Words for the explainer. The place name is a folder kind, never a path.
public enum FolderExplainerCopy {
    public static let usage = "GridBack shows a blurred copy of your wallpaper behind your apps. It only reads the wallpaper file."

    public static func placeName(_ place: WallpaperPathPlace) -> String {
        switch place {
        case .desktop: return "Desktop"
        case .documents: return "Documents"
        case .downloads: return "Downloads"
        case .icloud: return "iCloud Drive"
        case .volumes: return "a removable disk"
        case .pictures, .photosLibrary, .system, .other: return "that folder"
        }
    }

    public static func message(place: WallpaperPathPlace) -> String {
        switch place {
        case .volumes:
            return "Your wallpaper is on a removable disk. \(usage)"
        default:
            return "Your wallpaper is in \(placeName(place)). \(usage)"
        }
    }
}

/// The protected picture this desktop is using, judged from path text the caller already has.
public struct FolderWallpaperCandidate: Equatable, Sendable {
    public var path: String
    public var place: WallpaperPathPlace

    public init(path: String, place: WallpaperPathPlace) {
        self.path = path
        self.place = place
    }
}

public enum FolderAskTargeting {
    /// A colour, an Aerial, a folder of pictures, or a file that is already being shown returns nil.
    /// This does not open the file.
    public static func protectedPicture(
        provider: String?,
        isFolder: Bool,
        storePaths: [String],
        workspacePath: String?,
        resolvedUseIsFile: Bool
    ) -> FolderWallpaperCandidate? {
        if resolvedUseIsFile || isFolder { return nil }
        if let provider, provider != WallpaperStoreIndex.imageProvider { return nil }
        for raw in storePaths {
            let path = WallpaperPathPlace.normalized(raw)
            let place = WallpaperPathPlace.classify(path)
            if place.isProtected {
                return FolderWallpaperCandidate(path: path, place: place)
            }
        }
        if storePaths.isEmpty, let workspacePath {
            let path = WallpaperPathPlace.normalized(workspacePath)
            let place = WallpaperPathPlace.classify(path)
            if place.isProtected {
                return FolderWallpaperCandidate(path: path, place: place)
            }
        }
        return nil
    }
}

/// Whether the deliberate read may open the file.
/// An iCloud file that is not already on this Mac stays closed so it is not downloaded.
public enum FolderProbePlan {
    public static func shouldOpen(place: WallpaperPathPlace, alreadyLocal: Bool) -> Bool {
        guard FolderAccessRules.askable.contains(place) else { return false }
        if !FolderAccessRules.allowsDownload(place), !alreadyLocal { return false }
        return true
    }
}
