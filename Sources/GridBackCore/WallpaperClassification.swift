import CoreFoundation
import Foundation

/// How the desktop picture behind the grid should be chosen.
/// A time-of-day photo is not one frame. A downloaded Aerial can supply one frame from its local movie.
public enum WallpaperKind: String, Equatable, Sendable {
    case still
    case lightDark
    case timeBased
    case solidColor
    case aerialOrUnknown
    case unreadable
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
        case .timeBased, .aerialOrUnknown, .solidColor, .unreadable, .fallback:
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
    /// The colour provider's `systemColor` when it is a short name, not a path.
    public var systemColorName: String?
    /// Public description of `systemColor` and `type` for the colour provider. Capped.
    public var colorValueLog: String
    /// Parsed picture candidates, in order. The first readable one is used.
    public var imageCandidates: [String]
    public var bookmarks: [Data]
    public var urlShape: String
    public var filesCount: Int
    /// Key names and value types for a colour choice. No paths.
    public var structureLog: String
    /// A keyed archive that may be an NSColor. The app unarchives it.
    public var archivedColor: Data?
    /// A Desktop, Documents, Downloads, or Photos library path must not be opened.
    public var locationBlocked: Bool
    /// When the store file cannot be read, a real legacy photo URL may be used.
    public var allowLegacy: Bool
    /// Aerial asset id from the choice, when the store named one. Not a path.
    public var aerialAssetID: String?
    /// Aerial subcategory id, when the store named no asset. Not a path.
    public var aerialSubcategory: String?
    /// `Desktop` or `Linked` for an Aerial. Empty for every other provider.
    public var aerialRecord: String

    public init(
        provider: String,
        configKeys: [String],
        imageFilePath: String?,
        isFolder: Bool,
        solidColor: WallpaperSolidColor?,
        solidColorImagePath: String?,
        systemColorName: String? = nil,
        colorValueLog: String = "",
        imageCandidates: [String] = [],
        bookmarks: [Data] = [],
        urlShape: String = "none",
        filesCount: Int = 0,
        structureLog: String = "",
        archivedColor: Data? = nil,
        locationBlocked: Bool = false,
        allowLegacy: Bool = true,
        aerialAssetID: String? = nil,
        aerialSubcategory: String? = nil,
        aerialRecord: String = ""
    ) {
        self.provider = provider
        self.configKeys = configKeys
        self.imageFilePath = imageFilePath
        self.isFolder = isFolder
        self.solidColor = solidColor
        self.solidColorImagePath = solidColorImagePath
        self.systemColorName = systemColorName
        self.colorValueLog = colorValueLog
        self.imageCandidates = imageCandidates
        self.bookmarks = bookmarks
        self.urlShape = urlShape
        self.filesCount = filesCount
        self.structureLog = structureLog
        self.archivedColor = archivedColor
        self.locationBlocked = locationBlocked
        self.allowLegacy = allowLegacy
        self.aerialAssetID = aerialAssetID
        self.aerialSubcategory = aerialSubcategory
        self.aerialRecord = aerialRecord
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
    public static let colorProvider = "com.apple.wallpaper.choice.color"
    public static let aerialsProvider = "com.apple.wallpaper.choice.aerials"
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
        // `Desktop` is this display's own choice. `Linked` is that choice when
        // it is shared by every Space. A colour or an Aerial is read from
        // `Linked`. A picture is not. `Idle` is the screen saver and is never read.
        guard let holder = contentHolder(in: entry),
              let content = holder.root["Content"] as? [String: Any],
              let choices = elements(content["Choices"]),
              let first = choices.first as? [String: Any],
              let provider = first["Provider"] as? String,
              !provider.isEmpty else {
            return nil
        }
        if holder.linkedOnly && provider != colorProvider && provider != aerialsProvider { return nil }
        let configuration = decodePropertyList(first["Configuration"]) ?? [:]
        let keys = configuration.keys.filter(isSafeKeyName).sorted()
        let folder = provider == imageFolderProvider
        let parsed = provider == imageProvider
            ? WallpaperURLParser.parse(url: configuration["url"], files: first["Files"])
            : WallpaperURLParser.empty
        let custom = provider == colorProvider ? customColor(configuration: configuration, content: content) : nil
        let found = provider == colorProvider && custom == nil && !isCustomColor(configuration)
            ? findColor(in: configuration, depth: 0)
            : (color: nil, imagePath: nil)
        let systemColor = configuration["systemColor"]
        let colorLog = provider == colorProvider
            ? WallpaperValueLog.colorProviderLine(systemColor: systemColor, type: configuration["type"])
            : ""
        let colorName = provider == colorProvider ? WallpaperSystemColor.enumName(from: systemColor) : nil
        let probe = provider == colorProvider
            ? WallpaperStructureProbe.inspect(
                desktop: holder.root,
                content: content,
                choice: first,
                configuration: configuration
            )
            : WallpaperStructureProbe.Result(line: "", archive: nil)
        let aerial = provider == aerialsProvider
            ? aerialIdentifiers(configuration: configuration, content: content)
            : (assetID: nil, subcategory: nil)
        return WallpaperStoreChoice(
            provider: provider,
            configKeys: keys,
            imageFilePath: parsed.paths.first,
            isFolder: folder,
            solidColor: custom ?? found.color,
            solidColorImagePath: found.imagePath,
            systemColorName: colorName,
            colorValueLog: colorLog,
            imageCandidates: parsed.paths,
            bookmarks: parsed.bookmarks,
            urlShape: parsed.shape,
            filesCount: parsed.filesCount,
            structureLog: probe.line,
            archivedColor: probe.archive,
            aerialAssetID: aerial.assetID,
            aerialSubcategory: aerial.assetID == nil ? aerial.subcategory : nil,
            aerialRecord: provider == aerialsProvider ? holder.record : ""
        )
    }

    /// The desktop record, and whether it came from the shared `Linked` choice.
    /// `Idle` is intentionally absent: that entry is the screen saver.
    private struct ContentHolder {
        var root: [String: Any]
        var linkedOnly: Bool
        var record: String
    }

    private static func contentHolder(in entry: [String: Any]) -> ContentHolder? {
        if let desktop = entry["Desktop"] as? [String: Any] {
            return ContentHolder(root: desktop, linkedOnly: false, record: "Desktop")
        }
        if let linked = entry["Linked"] as? [String: Any] {
            return ContentHolder(root: linked, linkedOnly: true, record: "Linked")
        }
        return nil
    }

    /// `assetID` in the configuration wins. A subcategory there is next. The
    /// encoded options beside the choice are used only when the configuration
    /// names neither. Data and text are opened with `decodePropertyList`, and
    /// the walk stops at the same depth as a custom colour.
    private static func aerialIdentifiers(
        configuration: [String: Any],
        content: [String: Any]
    ) -> (assetID: String?, subcategory: String?) {
        if let assetID = findToken("assetID", in: configuration, depth: 0) {
            return (assetID, nil)
        }
        if let subcategory = findToken("subcategory", in: configuration, depth: 0) {
            return (nil, subcategory)
        }
        guard let options = decodePropertyList(content["EncodedOptionValues"]) else {
            return (nil, nil)
        }
        if let assetID = findToken("assetID", in: options, depth: 0) {
            return (assetID, nil)
        }
        if let subcategory = findToken("subcategory", in: options, depth: 0) {
            return (nil, subcategory)
        }
        return (nil, nil)
    }

    /// A short token with no path characters. Anything else is not an id.
    private static func findToken(_ key: String, in value: Any?, depth: Int) -> String? {
        if depth > 8 { return nil }
        if value is Data || value is String {
            guard let expanded = decodePropertyList(value) else { return nil }
            return findToken(key, in: expanded, depth: depth + 1)
        }
        if let dictionary = value as? [String: Any] {
            if let token = WallpaperAerialCatalogue.safeToken(dictionary[key]) { return token }
            for name in dictionary.keys.sorted() {
                if let found = findToken(key, in: dictionary[name], depth: depth + 1) { return found }
            }
            return nil
        }
        if let list = elements(value) {
            for item in list {
                if let found = findToken(key, in: item, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// The colour from the + button. It is stored under `values.customColor`
    /// when `type` is `customColor`, either in the configuration or in the
    /// encoded options beside the choice. Any other type leaves that value
    /// unread. A missing or unexpected value is nil.
    private static func customColor(configuration: [String: Any], content: [String: Any]) -> WallpaperSolidColor? {
        guard isCustomColor(configuration) else { return nil }
        if let color = customColor(inValues: configuration["values"]) { return color }
        guard let options = decodePropertyList(content["EncodedOptionValues"]) else { return nil }
        return customColor(inValues: options["values"])
    }

    private static func isCustomColor(_ configuration: [String: Any]) -> Bool {
        configuration["type"] as? String == "customColor"
    }

    private static func customColor(inValues values: Any?) -> WallpaperSolidColor? {
        guard let values = decodePropertyList(values) else { return nil }
        return nestedColor(values["customColor"], depth: 0)
    }

    /// A custom colour may be the components themselves, or nested inside the
    /// option record. Data and text are decoded with the same property-list
    /// encodings as the configuration. Anything else is not a colour.
    private static func nestedColor(_ value: Any?, depth: Int) -> WallpaperSolidColor? {
        if depth > 8 { return nil }
        if let color = WallpaperColorReading.color(from: value) { return color }
        if value is Data || value is String, let expanded = decodePropertyList(value) {
            return nestedColor(expanded, depth: depth + 1)
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        let keys = dictionary.keys.sorted { lhs, rhs in
            let rank = colorKeyRank(lhs) - colorKeyRank(rhs)
            if rank != 0 { return rank < 0 }
            return lhs < rhs
        }
        for key in keys {
            if let color = nestedColor(dictionary[key], depth: depth + 1) { return color }
        }
        return nil
    }

    private static func colorKeyRank(_ key: String) -> Int {
        let lowered = key.lowercased()
        if lowered == "components" || lowered.contains("color") || lowered.contains("colour") { return 0 }
        return 1
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
            // A custom colour belongs only to a `customColor` choice. Other
            // types keep their own colour and do not read this leftover value.
            if key == "customColor" { continue }
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
        let absolute = trimmed.hasPrefix("/") || lowered.hasPrefix("file:")
        let resolved = absolute ? WallpaperPathPlace.normalized(trimmed) : decoded
        let fileName = (resolved as NSString).lastPathComponent
        guard !fileName.isEmpty, fileName.lowercased().hasSuffix(".png"), !fileName.contains("/") else { return nil }
        if absolute {
            guard resolved.lowercased().hasPrefix(solidColorsDirectory.lowercased() + "/") else {
                return nil
            }
            return resolved
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

public enum WallpaperNeutralFill {
    /// #E6E8EB in Light and #303238 in Dark. Already flat, so Reduce Transparency
    /// does not need a second material.
    public static func color(for appearance: WallpaperAppearance) -> WallpaperSolidColor {
        switch appearance {
        case .dark:
            return byteColor(0x30, 0x32, 0x38)
        case .light:
            return byteColor(0xE6, 0xE8, 0xEB)
        }
    }

    private static func byteColor(_ red: Int, _ green: Int, _ blue: Int) -> WallpaperSolidColor {
        WallpaperSolidColor(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}

public enum WallpaperSolidColorMatch {
    /// `Red Orange` matches `RedOrange.png` and `red orange.png`.
    public static func fileName(matching displayName: String, candidates: [String]) -> String? {
        let wanted = normalize(displayName)
        guard !wanted.isEmpty else { return nil }
        return candidates.first { normalize(stripExtension($0)) == wanted }
    }

    /// Letters and digits only, so `dustyRose` and `Dusty Rose.png` both become `dustyrose`.
    public static func normalize(_ name: String) -> String {
        let stem = (name as NSString).pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        return stem.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func stripExtension(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.hasSuffix(".png") { return String(name.dropLast(4)) }
        return name
    }
}

public enum WallpaperValueLog {
    public static let cap = 80

    /// `systemColor` and `type` only. Nested dictionaries keep key names and scalars.
    public static func colorProviderLine(systemColor: Any?, type: Any?) -> String {
        clip("systemColor=\(describe(systemColor)) type=\(describe(type))", cap * 3)
    }

    /// A short display name, or nil when the value is a path or too long to be a name.
    public static func shortName(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= cap, !trimmed.contains("/"), !trimmed.contains("~"), !trimmed.contains("..") else {
            return nil
        }
        return trimmed
    }

    public static func describe(_ value: Any?) -> String {
        if value == nil { return "none" }
        if let text = value as? String {
            return "String(\(clip(redacted(text), cap)))"
        }
        if let data = value as? Data {
            return "Data(\(data.count)bytes)"
        }
        if let dictionary = value as? [String: Any] {
            return "Dict(\(dictBody(dictionary, depth: 0)))"
        }
        if let list = value as? [Any] {
            return "Array(\(list.count))"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "Bool(\(number.boolValue))"
            }
            let double = number.doubleValue
            if double.rounded() == double, double < 1_000_000_000, double > -1_000_000_000 {
                return "Int(\(number.intValue))"
            }
            return "Double(\(String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), double)))"
        }
        return "Other"
    }

    private static func dictBody(_ dictionary: [String: Any], depth: Int) -> String {
        dictionary.keys.sorted().prefix(8).map { key in
            let name = clip(key, 24)
            let nested = dictionary[key]
            if depth == 0, let child = nested as? [String: Any] {
                return "\(name)=Dict(\(dictBody(child, depth: 1)))"
            }
            if nested is [String: Any] { return "\(name)=Dict" }
            if nested is [Any] { return "\(name)=Array" }
            return "\(name)=\(describe(nested))"
        }.joined(separator: ",")
    }

    private static func redacted(_ text: String) -> String {
        guard text.contains("/") || text.contains("~") else { return text }
        let name = (text as NSString).lastPathComponent
        return name.isEmpty ? "redacted" : name
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}

public struct WallpaperURLParse: Equatable, Sendable {
    public var shape: String
    public var filesCount: Int
    public var paths: [String]
    public var bookmarks: [Data]

    public init(shape: String, filesCount: Int, paths: [String], bookmarks: [Data]) {
        self.shape = shape
        self.filesCount = filesCount
        self.paths = paths
        self.bookmarks = bookmarks
    }
}

public enum WallpaperURLParser {
    public static let empty = WallpaperURLParse(shape: "none", filesCount: 0, paths: [], bookmarks: [])

    /// Reads a configuration `url` and a `Files` list. A relative `url` is joined
    /// to `base`. Bookmark bytes are kept only so the shape can be logged. They are
    /// never resolved: resolving a bookmark reads the file.
    public static func parse(url: Any?, files: Any?) -> WallpaperURLParse {
        let list = elements(files)
        var paths: [String] = []
        var bookmarks: [Data] = []
        collect(url, paths: &paths, bookmarks: &bookmarks)
        for item in list {
            collect(item, paths: &paths, bookmarks: &bookmarks)
        }
        return WallpaperURLParse(shape: shapeName(url), filesCount: list.count, paths: paths, bookmarks: bookmarks)
    }

    public static func shapeName(_ value: Any?) -> String {
        if value == nil { return "none" }
        if value is String { return "String" }
        if value is Data { return "Data" }
        if let dictionary = value as? [String: Any] {
            let keys = dictionary.keys.filter { !$0.contains("/") && $0.count <= 32 }.sorted().prefix(6)
            return keys.isEmpty ? "Dict" : "Dict(\(keys.joined(separator: ",")))"
        }
        return "Other"
    }

    private static func collect(_ value: Any?, paths: inout [String], bookmarks: inout [Data]) {
        if let data = value as? Data {
            bookmarks.append(data)
            return
        }
        if let path = absoluteFilePath(value) {
            paths.append(path)
            return
        }
        guard let dictionary = value as? [String: Any] else { return }
        if let data = dictionary["bookmark"] as? Data ?? dictionary["data"] as? Data {
            bookmarks.append(data)
        }
        if let relative = dictionary["relative"] as? String ?? dictionary["url"] as? String {
            if let path = absoluteFilePath(relative) {
                paths.append(path)
            } else if let base = dictionary["base"] as? String, let path = joined(relative: relative, base: base) {
                paths.append(path)
            }
        }
    }

    private static func joined(relative: String, base: String) -> String? {
        guard let baseURL = fileURL(base) else { return nil }
        let directory = baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
        let rooted = directory.path.hasSuffix("/") ? directory : URL(fileURLWithPath: directory.path + "/")
        guard let resolved = URL(string: relative, relativeTo: rooted)?.absoluteURL, resolved.isFileURL else {
            return nil
        }
        let path = WallpaperPathPlace.normalized(resolved.path)
        return path == "/" ? nil : path
    }

    private static func absoluteFilePath(_ value: Any?) -> String? {
        guard let raw = value as? String, !raw.isEmpty else { return nil }
        if raw.hasPrefix("~") {
            let path = WallpaperPathPlace.normalized(raw)
            return path.isEmpty ? nil : path
        }
        if let url = fileURL(raw), url.path.hasPrefix("/") {
            let path = WallpaperPathPlace.normalized(url.path)
            if path != "/", raw.contains(":") || raw.hasPrefix("/") { return path }
        }
        if raw.hasPrefix("/") {
            let path = WallpaperPathPlace.normalized(raw)
            return path == "/" ? nil : path
        }
        return nil
    }

    private static func fileURL(_ raw: String) -> URL? {
        let encoded = raw.replacingOccurrences(of: " ", with: "%20")
        for candidate in [raw, encoded] {
            if let url = URL(string: candidate), url.isFileURL { return url }
        }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        return nil
    }

    private static func elements(_ value: Any?) -> [Any] {
        if let list = value as? [Any] { return list }
        if let list = value as? NSArray { return Array(list) }
        return []
    }
}

public enum WallpaperPathPlace: String, Codable, CaseIterable, Equatable, Sendable {
    case desktop
    case documents
    case downloads
    case pictures
    case photosLibrary
    case icloud
    case volumes
    case system
    case other

    /// Folders that would raise a permission prompt. Pictures and system files are not in this list.
    public var isProtected: Bool {
        switch self {
        case .desktop, .documents, .downloads, .photosLibrary, .icloud, .volumes:
            return true
        case .pictures, .system, .other:
            return false
        }
    }

    /// The folder is decided from the path text alone. This does not touch the file.
    public static func classify(_ path: String) -> WallpaperPathPlace {
        let parts = lexicalParts(path)
        if parts.contains(where: { $0.lowercased().hasSuffix(".photoslibrary") }) {
            return .photosLibrary
        }
        if parts.first?.caseInsensitiveCompare("Volumes") == .orderedSame {
            return .volumes
        }
        if let folder = homeFolder(parts) {
            switch folder.name.lowercased() {
            case "desktop": return .desktop
            case "documents": return .documents
            case "downloads": return .downloads
            case "pictures": return .pictures
            case "library":
                if folder.rest.first?.caseInsensitiveCompare("Mobile Documents") == .orderedSame {
                    return .icloud
                }
            default:
                break
            }
        }
        if parts.first == "Library" || parts.first == "System" {
            return .system
        }
        return .other
    }

    /// A cleaned path with `.` and `..` removed. Symbolic links are not resolved.
    public static func normalized(_ path: String) -> String {
        let parts = lexicalParts(path)
        if parts.first == "~" {
            return "~/" + parts.dropFirst().joined(separator: "/")
        }
        return "/" + parts.joined(separator: "/")
    }

    public static func ext(of path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "none" : ext
    }

    private static func homeFolder(_ parts: [String]) -> (name: String, rest: [String])? {
        let start: Int
        if parts.first == "~" {
            start = 1
        } else if let users = parts.firstIndex(of: "Users") {
            start = users + 2
        } else {
            return nil
        }
        guard start < parts.count else { return nil }
        return (parts[start], Array(parts.dropFirst(start + 1)))
    }

    private static func lexicalParts(_ path: String) -> [String] {
        var text = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("file:") {
            let encoded = text.replacingOccurrences(of: " ", with: "%20")
            if let url = URL(string: encoded), url.isFileURL {
                text = url.path
            }
        }
        let home = text.hasPrefix("~")
        if home {
            text = String(text.dropFirst())
        }
        var parts: [String] = []
        for part in text.split(separator: "/") {
            if part == "." || part.isEmpty { continue }
            if part == ".." {
                if !parts.isEmpty, parts.last != "~" { parts.removeLast() }
                continue
            }
            parts.append(String(part))
        }
        if home { parts.insert("~", at: 0) }
        return parts
    }
}

/// Which of the given paths may be passed to the file system. Protected paths are omitted.
public enum WallpaperFileGate {
    public struct Plan: Equatable, Sendable {
        public var statPaths: [String]
        public var blockedPlace: WallpaperPathPlace?
        public var blockedExt: String
        public var pathParsed: Bool
    }

    public static func plan(paths: [String]) -> Plan {
        var statPaths: [String] = []
        var blockedPlace: WallpaperPathPlace?
        var blockedExt = "none"
        for path in paths {
            let normalized = WallpaperPathPlace.normalized(path)
            let place = WallpaperPathPlace.classify(normalized)
            if place.isProtected {
                if blockedPlace == nil {
                    blockedPlace = place
                    blockedExt = WallpaperPathPlace.ext(of: normalized)
                }
                continue
            }
            if normalized.hasPrefix("/") {
                statPaths.append(normalized)
            }
        }
        return Plan(
            statPaths: statPaths,
            blockedPlace: blockedPlace,
            blockedExt: blockedExt,
            pathParsed: !paths.isEmpty
        )
    }
}

public enum WallpaperURLLog {
    public static func line(
        shape: String,
        filesCount: Int,
        pathParsed: Bool,
        exists: String,
        readable: String,
        place: String,
        ext: String,
        reason: String
    ) -> String {
        "urlShape=\(shape) filesCount=\(filesCount) pathParsed=\(pathParsed) exists=\(exists) readable=\(readable) place=\(place) ext=\(ext) reason=\(reason)"
    }

    /// A protected folder was not checked. The line has no exists or readable field.
    public static func protected(shape: String, filesCount: Int, pathParsed: Bool, place: String, ext: String) -> String {
        "urlShape=\(shape) filesCount=\(filesCount) pathParsed=\(pathParsed) place=\(place) skipped=protected ext=\(ext)"
    }
}

public enum WallpaperSystemColor {
    /// A one-key dictionary whose value is an empty dictionary. The key is the colour name.
    public static func enumName(from value: Any?) -> String? {
        guard let dictionary = value as? [String: Any], dictionary.count == 1, let key = dictionary.keys.first else {
            return nil
        }
        guard let child = dictionary[key] as? [String: Any], child.isEmpty else { return nil }
        guard !key.isEmpty, key.count <= 64, !key.contains("/"), !key.contains("~") else { return nil }
        return key
    }
}

public enum WallpaperKeyedArchive {
    public static func isKeyedArchive(_ data: Data) -> Bool {
        guard data.count >= 8, data.starts(with: Data("bplist".utf8)) else { return false }
        return data.range(of: Data("$archiver".utf8)) != nil
    }
}

public enum WallpaperStructureProbe {
    public struct Result: Equatable, Sendable {
        public var line: String
        public var archive: Data?
    }

    /// Key names and value types only, three levels deep. Numbers are shown for
    /// colour keys. Strings that contain a slash are omitted.
    public static func inspect(
        desktop: [String: Any],
        content: [String: Any],
        choice: [String: Any],
        configuration: [String: Any] = [:]
    ) -> Result {
        var archive: Data?
        var line = "Desktop(\(describe(desktop, depth: 1, archive: &archive))) Content(\(describe(content, depth: 1, archive: &archive))) Choice(\(describe(choice, depth: 1, archive: &archive)))"
        if choice["Configuration"] is Data, !configuration.isEmpty {
            line += " Config(\(describe(configuration, depth: 1, archive: &archive)))"
        }
        return Result(line: clip(line, 480), archive: archive)
    }

    private static func describe(_ value: Any, depth: Int, archive: inout Data?) -> String {
        if let data = value as? Data {
            if archive == nil, WallpaperKeyedArchive.isKeyedArchive(data) { archive = data }
            return WallpaperKeyedArchive.isKeyedArchive(data) ? "Data(keyedArchive)" : "Data"
        }
        if let text = value as? String {
            return text.contains("/") || text.contains("~") ? "" : "String"
        }
        if let dictionary = value as? [String: Any] {
            guard depth <= 3 else { return "Dict" }
            let body = dictionary.keys.sorted().prefix(8).compactMap { key -> String? in
                let child = describe(dictionary[key] as Any, depth: depth + 1, archive: &archive)
                if child.isEmpty { return nil }
                if showsNumbers(key), let numbers = numberText(dictionary[key]) {
                    return "\(clip(key, 24))=\(numbers)"
                }
                return "\(clip(key, 24))=\(child)"
            }.joined(separator: ",")
            return "Dict(\(body))"
        }
        if let list = value as? [Any] {
            return "Array(\(list.count))"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return "Bool" }
            return number.doubleValue.rounded() == number.doubleValue ? "Int" : "Double"
        }
        if value is Date { return "Date" }
        return "Other"
    }

    private static func showsNumbers(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.contains("color") || lowered.contains("component")
    }

    private static func numberText(_ value: Any?) -> String? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), number.doubleValue)
        }
        let numbers: [Double]
        if let list = value as? [Double] {
            numbers = list
        } else if let list = value as? [Int] {
            numbers = list.map(Double.init)
        } else if let list = value as? [NSNumber] {
            numbers = list.map(\.doubleValue)
        } else if let list = value as? [Any] {
            let parsed = list.compactMap { item -> Double? in
                guard let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
                return number.doubleValue
            }
            guard parsed.count == list.count else { return nil }
            numbers = parsed
        } else {
            return nil
        }
        guard !numbers.isEmpty else { return nil }
        let text = numbers.prefix(6).map {
            String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0)
        }.joined(separator: ",")
        return "[\(text)]"
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}

public enum WallpaperDim {
    /// The same black veil on every backdrop, so pale colours stay readable.
    public static let black = 0.25
}

/// One local Aerial movie. Remote addresses in the catalogue are ignored.
/// The video file is always `videos/<assetID>.mov` under the directory the caller passes.
public enum WallpaperAerialCatalogue {
    /// How far into the movie the still is taken.
    public static let frameFraction = 0.25

    /// A stored asset id wins. A subcategory is mapped through the catalogue.
    /// An unknown subcategory, or a value that is not a short token, is nil.
    public static func resolvedAssetID(storedAssetID: String?, subcategory: String?, catalogue: Any?) -> String? {
        if let storedAssetID {
            return safeToken(storedAssetID)
        }
        guard let subcategory = safeToken(subcategory) else { return nil }
        return representativeAssetID(forSubcategory: subcategory, in: catalogue)
    }

    public static func representativeAssetID(forSubcategory subcategory: String, in catalogue: Any?) -> String? {
        guard let wanted = safeToken(subcategory), let root = jsonObject(catalogue) else { return nil }
        guard let categories = root["categories"] as? [Any] else { return nil }
        for category in categories {
            guard let category = category as? [String: Any],
                  let subs = category["subcategories"] as? [Any] else { continue }
            for item in subs {
                guard let sub = item as? [String: Any], safeToken(sub["id"]) == wanted else { continue }
                return safeToken(sub["representativeAssetID"])
            }
        }
        return nil
    }

    /// File URLs for the assets in a catalogue. An `https` entry is not returned.
    public static func localVideoURLs(in catalogue: Any?, videosDirectory: URL) -> [URL] {
        guard let root = jsonObject(catalogue), let assets = root["assets"] as? [Any] else { return [] }
        var urls: [URL] = []
        var seen = Set<String>()
        for asset in assets {
            guard let asset = asset as? [String: Any],
                  let id = safeToken(asset["id"]),
                  seen.insert(id).inserted,
                  let url = localVideoURL(assetID: id, videosDirectory: videosDirectory) else { continue }
            urls.append(url)
        }
        return urls
    }

    public static func localVideoURL(assetID: String, videosDirectory: URL) -> URL? {
        guard videosDirectory.isFileURL, videosDirectory.scheme?.lowercased() == "file" else { return nil }
        guard let assetID = safeToken(assetID) else { return nil }
        let url = videosDirectory.appendingPathComponent(assetID + ".mov", isDirectory: false)
        guard url.isFileURL, url.scheme?.lowercased() == "file", url.lastPathComponent == assetID + ".mov" else {
            return nil
        }
        return url
    }

    /// The local movie when it is already on disk. A missing file is nil, and nothing is downloaded.
    public static func localMovie(assetID: String?, videosDirectory: URL) -> URL? {
        guard let assetID, let url = localVideoURL(assetID: assetID, videosDirectory: videosDirectory) else {
            return nil
        }
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else {
            return nil
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    /// A missing movie, an unknown id, or no id is the plain fallback.
    public static func kind(assetID: String?, videosDirectory: URL) -> WallpaperKind {
        localMovie(assetID: assetID, videosDirectory: videosDirectory) == nil ? .fallback : .still
    }

    public static func safeToken(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        for scalar in trimmed.unicodeScalars {
            let allowed = CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
            if !allowed { return nil }
        }
        return trimmed
    }

    private static func jsonObject(_ catalogue: Any?) -> [String: Any]? {
        if let dictionary = catalogue as? [String: Any] { return dictionary }
        if let data = catalogue as? Data,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return nil
    }
}

public enum WallpaperAerialLog {
    /// Which store record supplied the Aerial. Keys and the provider only.
    public static func recordLine(record: String, provider: String, keys: [String]) -> String {
        let safeRecord = record == "Desktop" || record == "Linked" ? record : "none"
        let safeProvider = provider.contains("/") || provider.contains("~") || provider.contains("..") || provider.count > 80
            ? "redacted"
            : provider
        return "record=\(safeRecord) provider=\(safeProvider) keys=\(WallpaperLogName.configKeys(keys))"
    }

    /// `matched` and, when it is a short token, the asset id. Never a path.
    public static func matchLine(matched: Bool, assetID: String?) -> String {
        let flag = matched ? "true" : "false"
        guard let assetID, let token = WallpaperAerialCatalogue.safeToken(assetID) else {
            return "matched=\(flag)"
        }
        return "matched=\(flag) assetID=\(token)"
    }
}

public enum WallpaperChoicePolicy {
    /// Only the image provider's file is opened. A colour provider uses a mapped
    /// colour. Aerials do not use the legacy picture URL; a local movie is chosen
    /// separately. Every other stored provider is `aerialOrUnknown`.
    /// A store file that exists but cannot be read is a known limit: the legacy
    /// URL is not used to get around that. A missing store file may use the legacy URL.
    /// The placeholder `DefaultDesktop` file is never treated as the user's choice.
    public static func resolve(
        choice: WallpaperStoreChoice?,
        workspacePath: String?,
        imageFileReadable: Bool,
        storeFileExists: Bool = false
    ) -> (source: WallpaperSource, use: WallpaperUse, kind: WallpaperKind) {
        if let choice {
            if choice.provider == WallpaperStoreIndex.imageProvider, !choice.isFolder {
                if choice.locationBlocked || choice.imageFilePath.map(WallpaperPathPlace.classify)?.isProtected == true {
                    return (.store, .plainBlur, .fallback)
                }
                if let path = choice.imageFilePath, imageFileReadable, !choice.locationBlocked {
                    return (.store, .imageFile(path), .still)
                }
                if storeFileExists, !imageFileReadable, !choice.locationBlocked {
                    return (.store, .plainBlur, .unreadable)
                }
                if choice.allowLegacy, !choice.locationBlocked, let legacy = legacyFile(workspacePath) {
                    return (.legacy, .imageFile(legacy), .still)
                }
                if let workspacePath, WallpaperPathPlace.classify(workspacePath).isProtected {
                    return (.legacy, .plainBlur, .fallback)
                }
                return (.store, .plainBlur, .aerialOrUnknown)
            }
            if choice.provider == WallpaperStoreIndex.colorProvider, let color = choice.solidColor {
                return (.store, .solid(color), .solidColor)
            }
            return (.store, .plainBlur, .aerialOrUnknown)
        }
        if let workspacePath, WallpaperPathPlace.classify(workspacePath).isProtected {
            return (.legacy, .plainBlur, .fallback)
        }
        if let legacy = legacyFile(workspacePath) {
            return (.legacy, .imageFile(legacy), .still)
        }
        return (.none, .plainBlur, .fallback)
    }

    private static func legacyFile(_ path: String?) -> String? {
        guard let path, !path.isEmpty, !WallpaperReportedImage.isSystemDefault(path) else { return nil }
        if WallpaperPathPlace.classify(path).isProtected { return nil }
        return WallpaperPathPlace.normalized(path)
    }
}

/// A prepared picture is kept when it is still the one asked for, including
/// when the grid is not open yet. A picture that failed is not kept.
public enum WallpaperPictureStore {
    public static func shouldKeep(hasPicture: Bool, completedCacheKey: String, currentCacheKey: String) -> Bool {
        hasPicture && !completedCacheKey.isEmpty && completedCacheKey == currentCacheKey
    }

    /// The part of a cache key that names the picture. A path is not interpreted here.
    public static func cacheToken(_ cacheKey: String) -> String {
        guard let bar = cacheKey.firstIndex(of: "|") else { return cacheKey }
        return String(cacheKey[..<bar])
    }

    /// The plain picture kept while a folder was refused. Once that folder is allowed,
    /// this picture is not the wallpaper and must not be shown again.
    public static func shouldDropRefusedFallback(cacheKey: String, accessAllowed: Bool) -> Bool {
        guard accessAllowed, !cacheKey.isEmpty else { return false }
        switch cacheToken(cacheKey) {
        case "protected", "unreadable":
            return true
        default:
            return false
        }
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
