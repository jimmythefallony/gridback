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

/// The choice recorded for one display. A file path is the picture to read.
/// Anything else is not a single still GridBack can show.
public struct WallpaperConfiguredChoice: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case file(path: String)
        case solidColor
        case aerial
        case notAPicture
    }

    public var role: Role
    /// Flat colour recorded with the choice, when the store has one.
    public var color: WallpaperSolidColor?
    /// A title such as "Golden Gate" that can be matched to a system picture.
    public var pictureName: String?
    public var lastSet: TimeInterval

    public init(
        role: Role,
        color: WallpaperSolidColor? = nil,
        pictureName: String? = nil,
        lastSet: TimeInterval = 0
    ) {
        self.role = role
        self.color = color
        self.pictureName = pictureName
        self.lastSet = lastSet
    }
}

public enum WallpaperColorComponents {
    /// `backgroundColor.components` from the wallpaper store. One value is grey.
    /// Three or four values are red, green, blue, and an optional alpha.
    public static func color(from value: Any?) -> WallpaperSolidColor? {
        let source = (value as? [String: Any])?["components"] ?? value
        let numbers = doubles(source)
        let rgb: (Double, Double, Double)
        switch numbers.count {
        case 1, 2:
            rgb = (numbers[0], numbers[0], numbers[0])
        case 3...:
            rgb = (numbers[0], numbers[1], numbers[2])
        default:
            return nil
        }
        func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
        return WallpaperSolidColor(red: unit(rgb.0), green: unit(rgb.1), blue: unit(rgb.2))
    }

    private static func doubles(_ value: Any?) -> [Double] {
        if let list = value as? [Double] { return list }
        if let list = value as? [NSNumber] { return list.map(\.doubleValue) }
        if let list = value as? [Any] { return list.compactMap(double) }
        if let list = value as? NSArray { return list.compactMap(double) }
        return []
    }

    private static func double(_ value: Any) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        return nil
    }
}

public enum WallpaperProviderRole {
    public static let image = "com.apple.wallpaper.choice.image"
    public static let dynamic = "com.apple.wallpaper.choice.dynamic"
    public static let aerials = "com.apple.wallpaper.choice.aerials"
    public static let screenSaver = "com.apple.wallpaper.choice.screen-saver"

    public static func role(provider: String, configuration: [String: Any], filePath: String?) -> WallpaperConfiguredChoice.Role {
        let lowered = provider.lowercased()
        let type = (configuration["type"] as? String)?.lowercased()
        let placeholder = filePath.map(WallpaperReportedImage.isSystemDefault) ?? false
        let realPath = (filePath?.isEmpty == false && !placeholder) ? filePath : nil
        if lowered.contains("aerial") || lowered.contains("screen-saver") || lowered.contains("screensaver") {
            return .aerial
        }
        if let realPath {
            return .file(path: realPath)
        }
        if lowered.contains("color") || lowered.contains("gradient") || type == "color" {
            return .solidColor
        }
        if WallpaperColorComponents.color(from: configuration["backgroundColor"]) != nil {
            return .solidColor
        }
        return .notAPicture
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
        let workspacePicture = realPicture(workspacePath)
        if let configured {
            switch configured.role {
            case .file(let path):
                if WallpaperReportedImage.isSystemDefault(path) {
                    return workspacePicture.map { .file(path: $0) } ?? .plainBlur
                }
                if let workspacePicture, workspacePicture != path {
                    return .file(path: workspacePicture)
                }
                return .file(path: path)
            case .solidColor:
                return .solidColor
            case .aerial, .notAPicture:
                if let workspacePicture {
                    return .file(path: workspacePicture)
                }
                return .plainBlur
            }
        }
        if let workspacePicture {
            return .file(path: workspacePicture)
        }
        return .plainBlur
    }

    private static func realPicture(_ path: String?) -> String? {
        guard let path, !path.isEmpty, !WallpaperReportedImage.isSystemDefault(path) else { return nil }
        return path
    }
}

/// The desktop picture macOS names when it will not name the real wallpaper.
public enum WallpaperReportedImage {
    public static let systemDefaultPath = "/System/Library/CoreServices/DefaultDesktop.heic"

    public static func isSystemDefault(_ path: String) -> Bool {
        (path as NSString).lastPathComponent.caseInsensitiveCompare("DefaultDesktop.heic") == .orderedSame
    }
}

public enum WallpaperStoreIndex {
    /// The desktop choice for this display. A per-display entry wins. A global
    /// entry is used when this display has none. Old per-Space entries are left
    /// unread: the display entry is the one macOS updates.
    public static func choice(in store: [String: Any], displayUUID: String?) -> WallpaperConfiguredChoice? {
        var layers: [WallpaperLayer] = []
        if let displayUUID,
           let displays = store["Displays"] as? [String: Any],
           let entry = displayEntry(displays, uuid: displayUUID),
           let choice = choice(inEntry: entry) {
            layers.append(WallpaperLayer(choice: choice, specificity: 2))
        }
        if let entry = store["AllSpacesAndDisplays"] as? [String: Any],
           let choice = choice(inEntry: entry) {
            layers.append(WallpaperLayer(choice: choice, specificity: 1))
        }
        if let entry = store["SystemDefault"] as? [String: Any],
           let choice = choice(inEntry: entry) {
            layers.append(WallpaperLayer(choice: choice, specificity: 0))
        }
        return WallpaperLayerPicker.pick(layers)
    }

    private static func choice(inEntry entry: [String: Any]) -> WallpaperConfiguredChoice? {
        guard let desktop = desktop(of: entry),
              let content = desktop["Content"] as? [String: Any],
              let choices = elements(content["Choices"]) else {
            return nil
        }
        let parsed = choices.compactMap { item -> WallpaperConfiguredChoice? in
            guard let choice = item as? [String: Any], let provider = choice["Provider"] as? String else { return nil }
            let configuration = configurationDictionary(choice["Configuration"])
            let path = filePath(configuration: configuration, files: choice["Files"]) ?? fileURL(in: configuration)
            let color = WallpaperColorComponents.color(from: configuration["backgroundColor"])
            let name = pictureName(in: configuration, choice: choice)
            return WallpaperConfiguredChoice(
                role: WallpaperProviderRole.role(provider: provider, configuration: configuration, filePath: path),
                color: color,
                pictureName: name,
                lastSet: lastSet(of: desktop, entry: entry)
            )
        }
        let pictures = parsed.compactMap { choice -> String? in
            if case .file(let path) = choice.role, !WallpaperReportedImage.isSystemDefault(path) { return path }
            return nil
        }
        if Set(pictures).count > 1 {
            return WallpaperConfiguredChoice(role: .notAPicture, lastSet: parsed.first?.lastSet ?? 0)
        }
        return parsed.first
    }

    private static func fileURL(in value: Any?) -> String? {
        var found: [String] = []
        collectStrings(value, into: &found)
        for string in found {
            if let path = path(from: string), !WallpaperReportedImage.isSystemDefault(path) {
                return path
            }
        }
        return nil
    }

    private static func collectStrings(_ value: Any?, into list: inout [String]) {
        if let string = value as? String {
            list.append(string)
            return
        }
        if let dictionary = value as? [String: Any] {
            dictionary.values.forEach { collectStrings($0, into: &list) }
            return
        }
        if let listValue = elements(value) {
            listValue.forEach { collectStrings($0, into: &list) }
        }
    }

    private static func pictureName(in configuration: [String: Any], choice: [String: Any]) -> String? {
        let keys = ["name", "localizedName", "title", "wallpaperName", "baseName"]
        for source in [configuration, choice] {
            for key in keys {
                if let name = source[key] as? String, WallpaperSystemPicture.isPictureTitle(name) {
                    return name
                }
            }
        }
        return nil
    }

    private static func lastSet(of desktop: [String: Any], entry: [String: Any]) -> TimeInterval {
        for source in [desktop, entry] {
            if let date = source["LastSet"] as? Date { return date.timeIntervalSince1970 }
            if let date = source["LastUse"] as? Date { return date.timeIntervalSince1970 }
        }
        return 0
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

public struct WallpaperLayer: Equatable, Sendable {
    public var choice: WallpaperConfiguredChoice
    public var specificity: Int

    public init(choice: WallpaperConfiguredChoice, specificity: Int) {
        self.choice = choice
        self.specificity = specificity
    }
}

public enum WallpaperLayerPicker {
    /// The newest recorded choice wins. A tie keeps the choice for this display.
    public static func pick(_ layers: [WallpaperLayer]) -> WallpaperConfiguredChoice? {
        layers.max { lhs, rhs in
            if lhs.choice.lastSet != rhs.choice.lastSet {
                return lhs.choice.lastSet < rhs.choice.lastSet
            }
            return lhs.specificity < rhs.specificity
        }?.choice
    }
}

public enum WallpaperSystemPicture {
    public static let directories = [
        "/System/Library/Desktop Pictures",
        "/Library/Desktop Pictures"
    ]

    public static func isPictureTitle(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 80 else { return false }
        if trimmed.contains("/") || trimmed.contains("\\") || trimmed.contains("..") { return false }
        if trimmed.contains("com.apple") { return false }
        if trimmed.range(of: #"^[0-9A-Fa-f-]{32,36}$"#, options: .regularExpression) != nil { return false }
        return trimmed.rangeOfCharacter(from: .letters) != nil
    }

    public static func candidatePaths(name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPictureTitle(trimmed) else { return [] }
        var paths: [String] = []
        for directory in directories {
            for ext in ["heic", "HEIC", "jpg", "jpeg", "png"] {
                paths.append("\(directory)/\(trimmed).\(ext)")
            }
        }
        return paths
    }
}

public enum WallpaperLogName {
    /// The file's own name, never the folders that lead to it.
    public static func fileName(path: String?) -> String {
        guard let path, !path.isEmpty else { return "none" }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "none" : name
    }
}

public enum WallpaperDecisionReason: String, Equatable, Sendable {
    case lightDark
    case still
    case timeOfDay
    case aerial
    case solidColor
    case solidImage
    case placeholderUnidentified
    case unreadable
    case noPicture
}

public enum WallpaperImageExtent {
    public static let solidPixelLimit = 32

    public static func isTinySolidCandidate(pixelWidth: Int, pixelHeight: Int) -> Bool {
        pixelWidth > 0 && pixelHeight > 0 && max(pixelWidth, pixelHeight) <= solidPixelLimit
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
    /// A fill colour is the wallpaper for a colour choice, or when the only
    /// reported file is the system placeholder. A photo's fill colour is the gap
    /// around Fit and Center, which this blur does not reconstruct.
    public static func applies(
        selection: WallpaperSelection,
        hasWorkspaceImage: Bool,
        hasFillColor: Bool,
        workspaceIsPlaceholder: Bool = false
    ) -> Bool {
        guard hasFillColor else { return false }
        switch selection {
        case .file:
            return false
        case .solidColor:
            return true
        case .plainBlur:
            return workspaceIsPlaceholder || !hasWorkspaceImage
        }
    }
}

public enum WallpaperBackdropPlan: Equatable, Sendable {
    case picture(path: String, index: Int, kind: WallpaperKind, reason: WallpaperDecisionReason)
    case solidColor(kind: WallpaperKind, reason: WallpaperDecisionReason)
    case plainBlur(kind: WallpaperKind, reason: WallpaperDecisionReason)

    public var kind: WallpaperKind {
        switch self {
        case .picture(_, _, let kind, _), .solidColor(let kind, _), .plainBlur(let kind, _):
            return kind
        }
    }

    public var reason: WallpaperDecisionReason {
        switch self {
        case .picture(_, _, _, let reason), .solidColor(_, let reason), .plainBlur(_, let reason):
            return reason
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
        solidFillAvailable: Bool,
        knownColor: WallpaperSolidColor? = nil,
        imageIsTiny: Bool = false,
        plainReason: WallpaperDecisionReason = .noPicture
    ) -> WallpaperBackdropPlan {
        let colorIsKnown = solidFillAvailable || knownColor != nil
        switch selection {
        case .solidColor:
            if colorIsKnown {
                return .solidColor(kind: .solidColor, reason: .solidColor)
            }
            return .plainBlur(kind: .fallback, reason: plainReason == .noPicture ? .unreadable : plainReason)
        case .plainBlur:
            if colorIsKnown {
                return .solidColor(kind: .solidColor, reason: .solidColor)
            }
            let reason = plainReason == .noPicture ? .placeholderUnidentified : plainReason
            let kind: WallpaperKind = reason == .aerial ? .aerialOrUnknown : .fallback
            return .plainBlur(kind: kind, reason: reason)
        case .file(let path):
            if fileIsDirectory || imageCount <= 0 {
                if colorIsKnown {
                    return .solidColor(kind: .solidColor, reason: .solidColor)
                }
                return .plainBlur(kind: .fallback, reason: .unreadable)
            }
            let kind = WallpaperClassifier.kind(hints: hints, imageCount: imageCount)
            switch WallpaperClassifier.frame(
                kind: kind,
                hints: hints,
                appearance: appearance,
                imageCount: imageCount
            ) {
            case .index(let index):
                if imageIsTiny, colorIsKnown {
                    return .solidColor(kind: .solidColor, reason: .solidImage)
                }
                let reason: WallpaperDecisionReason = kind == .lightDark ? .lightDark : .still
                return .picture(path: path, index: index, kind: kind, reason: reason)
            case .plainBlur:
                let reason: WallpaperDecisionReason = kind == .timeBased ? .timeOfDay : .unreadable
                return .plainBlur(kind: kind, reason: reason)
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
