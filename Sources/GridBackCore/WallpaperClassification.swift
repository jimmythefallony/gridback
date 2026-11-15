import Foundation

/// How the desktop picture behind the grid should be chosen.
/// Time-of-day and moving wallpapers are not a single frame GridBack can name.
public enum WallpaperKind: String, Equatable, Sendable {
    case still
    case lightDark
    case timeBased
    case aerialOrUnknown
}

/// The system appearance, not the appearance forced on the grid window.
public enum WallpaperAppearance: String, Equatable, Sendable {
    case light
    case dark
}

/// One frame of a wallpaper file, or no frame at all.
public enum WallpaperFrame: Equatable, Sendable {
    case index(Int)
    case plainBlur
}

/// What the wallpaper file claims, before it is trusted.
/// `apr`, `h24`, and `solar` are hints. A missing or unreadable value does not invent a frame.
public struct WallpaperMetadataHints: Equatable, Sendable {
    public var hasAppearanceTag: Bool
    public var lightIndex: Int?
    public var darkIndex: Int?
    public var hasTimeOfDay: Bool

    public init(hasAppearanceTag: Bool, lightIndex: Int?, darkIndex: Int?, hasTimeOfDay: Bool) {
        self.hasAppearanceTag = hasAppearanceTag
        self.lightIndex = lightIndex
        self.darkIndex = darkIndex
        self.hasTimeOfDay = hasTimeOfDay
    }

    public static let none = WallpaperMetadataHints(
        hasAppearanceTag: false,
        lightIndex: nil,
        darkIndex: nil,
        hasTimeOfDay: false
    )
}

public enum WallpaperMetadataDecoder {
    /// `apr` may name a light frame and a dark frame. `h24` and `solar` mean the
    /// picture changes through the day; their schedules are not read.
    public static func hints(aprBase64: String?, h24Base64: String?, solarBase64: String?) -> WallpaperMetadataHints {
        let pair = aprBase64.flatMap(appearanceIndices(base64:))
        return WallpaperMetadataHints(
            hasAppearanceTag: aprBase64 != nil,
            lightIndex: pair?.light,
            darkIndex: pair?.dark,
            hasTimeOfDay: h24Base64 != nil || solarBase64 != nil
        )
    }

    /// Light and dark indices from an `apr` payload. The pair may sit at the top
    /// or under `ap`. Indices are hints only: a bad payload yields none.
    public static func appearanceIndices(base64: String) -> (light: Int, dark: Int)? {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let entries = (plist["ap"] as? [String: Any]) ?? plist
        guard let light = integer(entries["l"]), let dark = integer(entries["d"]), light >= 0, dark >= 0 else {
            return nil
        }
        return (light, dark)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}

public enum WallpaperClassifier {
    /// A time-of-day hint wins over appearance. The frame on screen depends on the
    /// clock, and the light and dark stills inside that file are not that frame.
    public static func kind(hints: WallpaperMetadataHints, imageCount: Int) -> WallpaperKind {
        guard imageCount > 0 else { return .aerialOrUnknown }
        if hints.hasTimeOfDay { return .timeBased }
        if hints.hasAppearanceTag { return .lightDark }
        return .still
    }

    public static func frame(
        kind: WallpaperKind,
        hints: WallpaperMetadataHints,
        appearance: WallpaperAppearance,
        imageCount: Int
    ) -> WallpaperFrame {
        switch kind {
        case .timeBased, .aerialOrUnknown:
            return .plainBlur
        case .still:
            guard imageCount > 0 else { return .plainBlur }
            return .index(0)
        case .lightDark:
            let chosen = appearance == .dark ? hints.darkIndex : hints.lightIndex
            if let chosen, chosen >= 0, chosen < imageCount {
                return .index(chosen)
            }
            return .plainBlur
        }
    }
}

/// The choice recorded for one display. A file path is the picture to read.
/// Anything else is not a single still GridBack can show.
public struct WallpaperConfiguredChoice: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case file(path: String)
        case solidColor
        case notAPicture
    }

    public var role: Role

    public init(role: Role) {
        self.role = role
    }
}

public enum WallpaperProviderRole {
    public static let image = "com.apple.wallpaper.choice.image"
    public static let dynamic = "com.apple.wallpaper.choice.dynamic"
    public static let aerials = "com.apple.wallpaper.choice.aerials"
    public static let screenSaver = "com.apple.wallpaper.choice.screen-saver"

    public static func role(provider: String, configuration: [String: Any], filePath: String?) -> WallpaperConfiguredChoice.Role {
        let type = (configuration["type"] as? String)?.lowercased()
        if provider.lowercased().contains("color") || type == "color" {
            return .solidColor
        }
        switch provider {
        case image, dynamic:
            if let filePath, !filePath.isEmpty {
                return .file(path: filePath)
            }
            return .notAPicture
        default:
            return .notAPicture
        }
    }
}

/// What to read for the blur. The workspace image URL is only a fallback:
/// macOS reports the system default picture for some wallpapers that are not that file.
public enum WallpaperSelection: Equatable, Sendable {
    case file(path: String)
    case solidColor
    case plainBlur
}

public enum WallpaperSelectionResolver {
    public static func select(configured: WallpaperConfiguredChoice?, workspacePath: String?) -> WallpaperSelection {
        if let configured {
            switch configured.role {
            case .file(let path):
                // A different real file from NSWorkspace is newer than the stored choice.
                // The system default picture is not that: macOS reports it for wallpapers
                // that are not that file.
                if let workspacePath, !workspacePath.isEmpty, workspacePath != path,
                   !WallpaperReportedImage.isSystemDefault(workspacePath) {
                    return .file(path: workspacePath)
                }
                return .file(path: path)
            case .solidColor:
                return .solidColor
            case .notAPicture:
                return .plainBlur
            }
        }
        if let workspacePath, !workspacePath.isEmpty {
            return .file(path: workspacePath)
        }
        return .plainBlur
    }
}

/// The desktop picture macOS names when it will not name the real wallpaper.
public enum WallpaperReportedImage {
    public static let systemDefaultPath = "/System/Library/CoreServices/DefaultDesktop.heic"

    public static func isSystemDefault(_ path: String) -> Bool {
        path == systemDefaultPath
    }
}

public enum WallpaperStoreIndex {
    /// The desktop choice for this display. A per-display entry wins. A global
    /// entry is used when this display has none. Old per-Space entries are left
    /// unread: the display entry is the one macOS updates.
    public static func choice(in store: [String: Any], displayUUID: String?) -> WallpaperConfiguredChoice? {
        if let displayUUID,
           let displays = store["Displays"] as? [String: Any],
           let entry = displayEntry(displays, uuid: displayUUID),
           let choice = choice(inEntry: entry) {
            return choice
        }
        if let entry = store["AllSpacesAndDisplays"] as? [String: Any],
           let choice = choice(inEntry: entry) {
            return choice
        }
        if let entry = store["SystemDefault"] as? [String: Any],
           let choice = choice(inEntry: entry) {
            return choice
        }
        return nil
    }

    private static func choice(inEntry entry: [String: Any]) -> WallpaperConfiguredChoice? {
        guard let desktop = desktop(of: entry),
              let content = desktop["Content"] as? [String: Any],
              let choices = elements(content["Choices"]),
              let first = choices.first as? [String: Any],
              let provider = first["Provider"] as? String else {
            return nil
        }
        if choices.count != 1 {
            return WallpaperConfiguredChoice(role: .notAPicture)
        }
        let configuration = configurationDictionary(first["Configuration"])
        let path = filePath(configuration: configuration, files: first["Files"])
        return WallpaperConfiguredChoice(
            role: WallpaperProviderRole.role(provider: provider, configuration: configuration, filePath: path)
        )
    }

    private static func displayEntry(_ displays: [String: Any], uuid: String) -> [String: Any]? {
        let wanted = uuid.lowercased()
        let match = displays.first { $0.key.lowercased() == wanted }?.value
        return match as? [String: Any]
    }

    private static func desktop(of entry: [String: Any]) -> [String: Any]? {
        if (entry["Type"] as? String) == "linked" {
            return entry["Linked"] as? [String: Any]
        }
        return (entry["Desktop"] as? [String: Any]) ?? (entry["Linked"] as? [String: Any])
    }

    private static func elements(_ value: Any?) -> [Any]? {
        if let list = value as? [Any] { return list }
        if let list = value as? NSArray { return Array(list) }
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .collection else { return nil }
        let children = mirror.children.map(\.value)
        return children.isEmpty ? [] : children
    }

    private static func configurationDictionary(_ value: Any?) -> [String: Any] {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let data = value as? Data,
           let dictionary = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dictionary
        }
        return [:]
    }

    private static func filePath(configuration: [String: Any], files: Any?) -> String? {
        if let path = path(from: configuration["url"]) { return path }
        guard let files = elements(files), files.count == 1 else { return nil }
        if let first = files[0] as? [String: Any] {
            return path(from: first["relative"]) ?? path(from: first["url"])
        }
        return path(from: files[0])
    }

    private static func path(from value: Any?) -> String? {
        let raw: String?
        if let dictionary = value as? [String: Any] {
            raw = (dictionary["relative"] as? String) ?? (dictionary["url"] as? String)
        } else {
            raw = value as? String
        }
        guard let raw, !raw.isEmpty else { return nil }
        let encoded = raw.replacingOccurrences(of: " ", with: "%20")
        for candidate in [raw, encoded] {
            if let url = URL(string: candidate), url.isFileURL {
                return url.standardizedFileURL.path
            }
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL.path
        }
        return nil
    }
}

/// A prepared picture is kept when it is still the one asked for, including
/// when the grid is not open yet. A picture that failed is not kept.
public enum WallpaperPictureStore {
    public static func shouldKeep(hasPicture: Bool, completedCacheKey: String, currentCacheKey: String) -> Bool {
        hasPicture && !completedCacheKey.isEmpty && completedCacheKey == currentCacheKey
    }
}

public struct WallpaperSolidColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum WallpaperSolidFill {
    /// A fill colour is the wallpaper only for a colour choice, or when there is
    /// no picture URL at all. A photo's fill colour is the gap around Fit and Center,
    /// which this blur does not reconstruct.
    public static func applies(selection: WallpaperSelection, hasWorkspaceImage: Bool, hasFillColor: Bool) -> Bool {
        guard hasFillColor else { return false }
        switch selection {
        case .file:
            return false
        case .solidColor:
            return true
        case .plainBlur:
            return !hasWorkspaceImage
        }
    }
}

public enum WallpaperBackdropPlan: Equatable, Sendable {
    case picture(path: String, index: Int, kind: WallpaperKind)
    case solidColor(kind: WallpaperKind)
    case plainBlur(kind: WallpaperKind)

    public var kind: WallpaperKind {
        switch self {
        case .picture(_, _, let kind), .solidColor(let kind), .plainBlur(let kind):
            return kind
        }
    }
}

public enum WallpaperBackdropPlanner {
    public static func plan(
        selection: WallpaperSelection,
        hints: WallpaperMetadataHints,
        imageCount: Int,
        appearance: WallpaperAppearance,
        fileIsDirectory: Bool,
        solidFillAvailable: Bool
    ) -> WallpaperBackdropPlan {
        switch selection {
        case .solidColor:
            return solidFillAvailable ? .solidColor(kind: .still) : .plainBlur(kind: .aerialOrUnknown)
        case .plainBlur:
            return solidFillAvailable ? .solidColor(kind: .still) : .plainBlur(kind: .aerialOrUnknown)
        case .file(let path):
            if fileIsDirectory || imageCount <= 0 {
                return .plainBlur(kind: .aerialOrUnknown)
            }
            let kind = WallpaperClassifier.kind(hints: hints, imageCount: imageCount)
            switch WallpaperClassifier.frame(
                kind: kind,
                hints: hints,
                appearance: appearance,
                imageCount: imageCount
            ) {
            case .index(let index):
                return .picture(path: path, index: index, kind: kind)
            case .plainBlur:
                return .plainBlur(kind: kind)
            }
        }
    }
}

/// Identity of one blurred backdrop. Appearance is part of the key so a Light
/// frame is not reused after the system switches to Dark.
public enum WallpaperCacheIdentity {
    public static func key(
        token: String,
        pixelWidth: Int,
        pixelHeight: Int,
        appearance: WallpaperAppearance,
        kind: WallpaperKind,
        imageIndex: Int?
    ) -> String {
        let index = imageIndex.map(String.init) ?? "plain"
        return "\(token)|\(pixelWidth)x\(pixelHeight)|\(appearance.rawValue)|\(kind.rawValue)|\(index)"
    }
}
