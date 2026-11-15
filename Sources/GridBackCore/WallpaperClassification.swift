import Foundation

/// How the desktop picture behind the grid should be chosen.
/// Time-of-day and moving wallpapers are not a single frame GridBack can name.
public enum WallpaperKind: String, Equatable, Sendable {
    case still
    case lightDark
    case timeBased
    case solidColor
    case aerialOrUnknown
    case fallback
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
        case .timeBased, .aerialOrUnknown, .solidColor, .fallback:
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

/// Where the blur decision came from.
public enum WallpaperSource: String, Equatable, Sendable {
    case store
    case legacy
    case none
}

/// What to put behind the grid after the store and the legacy picture URL are read.
public enum WallpaperUse: Equatable, Sendable {
    case imageFile(String)
    case solid(WallpaperSolidColor)
    case plainBlur
}

/// One desktop choice from the wallpaper store. A sandboxed App Store build
/// cannot read that file, so callers then keep only a plain photo URL and use
/// the plain blur for everything else.
public struct WallpaperStoreChoice: Equatable, Sendable {
    public var provider: String
    /// Top-level names in the decoded configuration. Values are not kept for the log.
    public var configKeys: [String]
    /// Set only for the image provider when it names exactly one file.
    public var imageFilePath: String?
    public var isFolder: Bool
    public var solidColor: WallpaperSolidColor?
    /// A system Solid Colors image, only when the reference stays in that directory.
    public var solidColorImagePath: String?

    public init(
        provider: String,
        configKeys: [String],
        imageFilePath: String?,
        isFolder: Bool,
        solidColor: WallpaperSolidColor?,
        solidColorImagePath: String?
    ) {
        self.provider = provider
        self.configKeys = configKeys
        self.imageFilePath = imageFilePath
        self.isFolder = isFolder
        self.solidColor = solidColor
        self.solidColorImagePath = solidColorImagePath
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

public enum WallpaperStoreIndex {
    public static let imageProvider = "com.apple.wallpaper.choice.image"
    public static let imageFolderProvider = "com.apple.wallpaper.choice.image-folder"
    public static let solidColorsDirectory = "/System/Library/Desktop Pictures/Solid Colors"

    /// The desktop choice for this display, then the choice for every display,
    /// then the system default. Other displays are ignored. There is no
    /// "newest" guess. A missing or unexpected shape returns nil.
    public static func choice(in store: [String: Any], displayUUID: String?) -> WallpaperStoreChoice? {
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

    static func choice(inEntry entry: [String: Any]) -> WallpaperStoreChoice? {
        guard let desktop = entry["Desktop"] as? [String: Any],
              let content = desktop["Content"] as? [String: Any],
              let choices = elements(content["Choices"]),
              let first = choices.first as? [String: Any],
              let provider = first["Provider"] as? String,
              !provider.isEmpty else {
            return nil
        }
        let configuration = decodePropertyList(first["Configuration"]) ?? [:]
        let keys = configuration.keys.filter(isSafeKeyName).sorted()
        let folder = provider == imageFolderProvider
        let imagePath = provider == imageProvider ? singleImagePath(files: first["Files"], configuration: configuration) : nil
        let found = findColor(in: configuration, depth: 0)
        return WallpaperStoreChoice(
            provider: provider,
            configKeys: keys,
            imageFilePath: imagePath,
            isFolder: folder,
            solidColor: found.color,
            solidColorImagePath: found.imagePath
        )
    }

    static func decodePropertyList(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let data = value as? Data { return dictionary(from: data) }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
               let dictionary = dictionary(from: data) {
                return dictionary
            }
            if let data = trimmed.data(using: .utf8), let dictionary = dictionary(from: data) {
                return dictionary
            }
        }
        return nil
    }

    private static func dictionary(from data: Data) -> [String: Any]? {
        guard !data.isEmpty,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func displayEntry(_ displays: [String: Any], uuid: String) -> [String: Any]? {
        let wanted = uuid.lowercased()
        return displays.first { $0.key.lowercased() == wanted }?.value as? [String: Any]
    }

    private static func isSafeKeyName(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 64 && !key.contains("/") && !key.contains("\\") && !key.contains("..")
    }

    private static func singleImagePath(files: Any?, configuration: [String: Any]) -> String? {
        let listed = filePaths(in: files)
        if listed.count == 1 { return listed[0] }
        if !listed.isEmpty { return nil }
        let configured = filePaths(in: configuration["url"])
        return configured.count == 1 ? configured[0] : nil
    }

    private static func filePaths(in value: Any?) -> [String] {
        if let dictionary = value as? [String: Any] {
            if let path = path(from: dictionary["relative"] ?? dictionary["url"]) { return [path] }
            return []
        }
        guard let list = elements(value) else {
            if let path = path(from: value) { return [path] }
            return []
        }
        return list.compactMap { item in
            if let dictionary = item as? [String: Any] {
                return path(from: dictionary["relative"] ?? dictionary["url"])
            }
            return path(from: item)
        }
    }

    private static func path(from value: Any?) -> String? {
        guard let raw = value as? String, !raw.isEmpty else { return nil }
        let encoded = raw.replacingOccurrences(of: " ", with: "%20")
        for candidate in [raw, encoded] {
            if let url = URL(string: candidate), url.isFileURL {
                let path = url.standardizedFileURL.path
                if !path.isEmpty { return path }
            }
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL.path
        }
        return nil
    }

    private static func findColor(in value: Any?, depth: Int) -> (color: WallpaperSolidColor?, imagePath: String?) {
        if depth > 6 { return (nil, nil) }
        if let string = value as? String, let imagePath = solidColorImagePath(from: string) {
            return (nil, imagePath)
        }
        guard let dictionary = value as? [String: Any] else {
            if let list = elements(value) {
                for item in list {
                    let found = findColor(in: item, depth: depth + 1)
                    if found.color != nil || found.imagePath != nil { return found }
                }
            }
            return (nil, nil)
        }
        var imagePath: String?
        for (key, nested) in dictionary {
            if isColorKey(key), let color = WallpaperColorReading.color(from: nested) {
                return (color, imagePath)
            }
            let found = findColor(in: nested, depth: depth + 1)
            if found.color != nil { return found }
            if imagePath == nil { imagePath = found.imagePath }
        }
        return (nil, imagePath)
    }

    private static func isColorKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.contains("color") || lowered.contains("colour")
    }

    public static func solidColorImagePath(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let lowered = decoded.lowercased()
        guard lowered.contains("solid colors"), lowered.contains(".png") else { return nil }
        guard !trimmed.contains("..") else { return nil }
        let resolved = path(from: trimmed) ?? trimmed
        let fileName = (resolved as NSString).lastPathComponent
        guard !fileName.isEmpty, fileName.lowercased().hasSuffix(".png"), !fileName.contains("/") else { return nil }
        if trimmed.hasPrefix("/") || lowered.hasPrefix("file:") {
            guard let full = path(from: trimmed)?.lowercased(),
                  full.hasPrefix(solidColorsDirectory.lowercased() + "/") else {
                return nil
            }
            return path(from: trimmed)
        }
        return solidColorsDirectory + "/" + fileName
    }

    private static func elements(_ value: Any?) -> [Any]? {
        if let list = value as? [Any] { return list }
        if let list = value as? NSArray { return Array(list) }
        return nil
    }
}

public enum WallpaperColorReading {
    /// A colour value stored as grey, RGB, or RGB with alpha. Numbers above 1
    /// are treated as 0...255. Anything else is not a colour.
    public static func color(from value: Any?) -> WallpaperSolidColor? {
        if let dictionary = value as? [String: Any] {
            if let components = color(from: dictionary["components"]) { return components }
            if let red = number(dictionary["red"] ?? dictionary["r"]),
               let green = number(dictionary["green"] ?? dictionary["g"]),
               let blue = number(dictionary["blue"] ?? dictionary["b"]) {
                return color(numbers: [red, green, blue])
            }
            return nil
        }
        return color(numbers: numbers(from: value))
    }

    private static func color(numbers: [Double]) -> WallpaperSolidColor? {
        guard !numbers.isEmpty else { return nil }
        let scale = numbers.contains { $0 > 1 } ? 255.0 : 1.0
        func unit(_ value: Double) -> Double? {
            let scaled = value / scale
            guard scaled >= 0, scaled <= 1 else { return nil }
            return scaled
        }
        switch numbers.count {
        case 1, 2:
            guard let grey = unit(numbers[0]) else { return nil }
            return WallpaperSolidColor(red: grey, green: grey, blue: grey)
        case 3...:
            guard let red = unit(numbers[0]), let green = unit(numbers[1]), let blue = unit(numbers[2]) else {
                return nil
            }
            return WallpaperSolidColor(red: red, green: green, blue: blue)
        default:
            return nil
        }
    }

    private static func numbers(from value: Any?) -> [Double] {
        if let list = value as? [Double] { return list }
        if let list = value as? [NSNumber] { return list.map(\.doubleValue) }
        if let list = value as? [Any] { return list.compactMap(number) }
        if let list = value as? NSArray { return list.compactMap(number) }
        return []
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }
}

public enum WallpaperReportedImage {
    public static let systemDefaultPath = "/System/Library/CoreServices/DefaultDesktop.heic"

    public static func isSystemDefault(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.caseInsensitiveCompare("DefaultDesktop.heic") == .orderedSame
    }
}

public enum WallpaperChoicePolicy {
    /// The image provider's file is used when it can be read. A colour in the
    /// configuration is a flat fill. Every other stored choice uses a plain
    /// photo URL only when that URL is not the system placeholder.
    public static func resolve(
        choice: WallpaperStoreChoice?,
        workspacePath: String?,
        imageFileReadable: Bool
    ) -> (source: WallpaperSource, use: WallpaperUse) {
        let legacy = legacyFile(workspacePath)
        if let choice {
            if choice.provider == WallpaperStoreIndex.imageProvider,
               !choice.isFolder,
               let path = choice.imageFilePath,
               imageFileReadable {
                return (.store, .imageFile(path))
            }
            if let color = choice.solidColor {
                return (.store, .solid(color))
            }
            if let legacy {
                return (.legacy, .imageFile(legacy))
            }
            return (.store, .plainBlur)
        }
        if let legacy {
            return (.legacy, .imageFile(legacy))
        }
        return (.none, .plainBlur)
    }

    private static func legacyFile(_ path: String?) -> String? {
        guard let path, !path.isEmpty, !WallpaperReportedImage.isSystemDefault(path) else { return nil }
        return path
    }
}

/// A prepared picture is kept when it is still the one asked for, including
/// when the grid is not open yet. A picture that failed is not kept.
public enum WallpaperPictureStore {
    public static func shouldKeep(hasPicture: Bool, completedCacheKey: String, currentCacheKey: String) -> Bool {
        hasPicture && !completedCacheKey.isEmpty && completedCacheKey == currentCacheKey
    }
}

public enum WallpaperLogName {
    public static func fileName(path: String?) -> String {
        guard let path, !path.isEmpty else { return "none" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "none" : name
    }

    public static func configKeys(_ keys: [String]) -> String {
        let safe = keys.filter { !$0.isEmpty && !$0.contains("/") && $0.count <= 64 }
        return safe.isEmpty ? "none" : safe.sorted().joined(separator: ",")
    }
}

/// Identity of one blurred backdrop. Appearance is part of the key so a Light
/// frame is not reused after the system switches to Dark. The store's
/// modification time drops a cached blur after the wallpaper choice changes.
public enum WallpaperCacheIdentity {
    public static func key(
        token: String,
        pixelWidth: Int,
        pixelHeight: Int,
        appearance: WallpaperAppearance,
        kind: WallpaperKind,
        imageIndex: Int?,
        storeModified: TimeInterval = 0
    ) -> String {
        let index = imageIndex.map(String.init) ?? "plain"
        let stamp = storeModified.isFinite ? String(Int(storeModified.rounded())) : "0"
        return "\(token)|\(pixelWidth)x\(pixelHeight)|\(appearance.rawValue)|\(kind.rawValue)|\(index)|\(stamp)"
    }
}
