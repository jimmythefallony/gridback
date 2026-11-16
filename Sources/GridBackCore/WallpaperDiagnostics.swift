import CoreFoundation
import Foundation

/// A string may be written to the diagnostic log only when it cannot be a path.
/// Values shorter than 64 characters are kept. A slash, a backslash, or `~` hides the value.
public enum WallpaperDiagnosticText {
    public static let maxLength = 63

    public static func reveal(_ text: String, secrets: [String] = []) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        guard !trimmed.contains("/"), !trimmed.contains("\\"), !trimmed.contains("~") else { return nil }
        guard !trimmed.contains("\n"), !trimmed.contains("\r"), !trimmed.contains("\u{0}") else { return nil }
        let lowered = trimmed.lowercased()
        for token in secrets {
            let needle = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { continue }
            if needle.count >= 3, lowered == needle { return nil }
            if needle.count >= 8, lowered.contains(needle) { return nil }
        }
        return trimmed
    }
}

/// What an opaque wallpaper blob appears to be. A keyed archive is also a binary plist;
/// the archive marker wins so the two are not reported as the same kind.
public enum WallpaperDiagnosticDataKind: String, Equatable, Sendable {
    case bplist00 = "bplist00"
    case archiver = "contains $archiver"
    case json = "JSON"
    case other = "other"

    public static func detect(_ data: Data) -> WallpaperDiagnosticDataKind {
        if data.range(of: Data("$archiver".utf8)) != nil { return .archiver }
        if data.starts(with: Data("bplist00".utf8)) { return .bplist00 }
        if isJSONObject(data) { return .json }
        return .other
    }

    private static func isJSONObject(_ data: Data) -> Bool {
        var bytes = data[...]
        while let first = bytes.first, first == 0x20 || first == 0x09 || first == 0x0A || first == 0x0D {
            bytes = bytes.dropFirst()
        }
        guard let first = bytes.first, first == UInt8(ascii: "{") || first == UInt8(ascii: "[") else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) else { return false }
        return object is [Any] || object is [String: Any] || object is NSArray || object is NSDictionary
    }
}

public struct WallpaperDiagnosticFileStatus: Equatable, Sendable {
    public var exists: Bool
    public var readable: Bool
    /// The path was not opened. A protected folder, or a link into one, sets this.
    public var refused: Bool

    public init(exists: Bool, readable: Bool, refused: Bool) {
        self.exists = exists
        self.readable = readable
        self.refused = refused
    }
}

public struct WallpaperDiagnosticHEIC: Equatable, Sendable {
    public var h24: Bool
    public var solar: Bool
    public var apr: Bool
    public var frames: Int

    public init(h24: Bool, solar: Bool, apr: Bool, frames: Int) {
        self.h24 = h24
        self.solar = solar
        self.apr = apr
        self.frames = frames
    }
}

public struct WallpaperDiagnosticArchive: Equatable, Sendable {
    public var classNames: [String]
    public var components: [Double]

    public init(classNames: [String], components: [Double]) {
        self.classNames = classNames
        self.components = components
    }
}

/// File and archive answers supplied by the app. Tests pass a stand-in.
/// The report asks only for paths it has already classified as safe.
public struct WallpaperDiagnosticProbe {
    public var status: (String) -> WallpaperDiagnosticFileStatus
    public var read: (String) -> Data?
    public var heic: (String) -> WallpaperDiagnosticHEIC?
    public var unarchive: (Data) -> WallpaperDiagnosticArchive?

    public init(
        status: @escaping (String) -> WallpaperDiagnosticFileStatus,
        read: @escaping (String) -> Data?,
        heic: @escaping (String) -> WallpaperDiagnosticHEIC?,
        unarchive: @escaping (Data) -> WallpaperDiagnosticArchive?
    ) {
        self.status = status
        self.read = read
        self.heic = heic
        self.unarchive = unarchive
    }

    public static let closed = WallpaperDiagnosticProbe(
        status: { _ in WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: true) },
        read: { _ in nil },
        heic: { _ in nil },
        unarchive: { _ in nil }
    )
}

/// One diagnostic record for the wallpaper the grid is using.
/// The lines name keys and types. They do not name folders, accounts, or displays.
public enum WallpaperDiagnostics {
    public static let entriesJSONPath = "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"
    public static let customerDirectory = "/Library/Application Support/com.apple.idleassetsd/Customer"

    /// False for Desktop, Documents, Downloads, iCloud Drive, a Photos library, and external volumes.
    /// The decision uses the path text only.
    public static func allowsFileAccess(to path: String) -> Bool {
        let normalized = WallpaperPathPlace.normalized(path)
        guard normalized.hasPrefix("/") else { return false }
        return !WallpaperPathPlace.classify(normalized).isProtected
    }

    public static func lines(
        store: [String: Any]?,
        displayUUID: String?,
        legacyFileName: String,
        secrets: [String] = [],
        probe: WallpaperDiagnosticProbe
    ) -> [String] {
        var lines: [String] = []
        guard let store else {
            appendAbsent(legacyFileName: legacyFileName, secrets: secrets, to: &lines)
            return lines
        }
        let entry = select(store: store, displayUUID: displayUUID)
        let desktop = entry.flatMap { dictionary($0["Desktop"]) }
        let content = desktop.flatMap { dictionary($0["Content"]) }
        let choice = firstChoice(in: content)
        let provider = choice.flatMap { string($0["Provider"]) }
        let configurationValue = choice?["Configuration"]
        let configuration = configurationValue.flatMap(decodedDictionary)
        append("provider=\(shownProvider(provider, secrets: secrets))", secrets: secrets, to: &lines)
        append("entryKeys=\(keyList(entry, secrets: secrets))", secrets: secrets, to: &lines)
        if let choice {
            append("choice=\(describe(choice, secrets: secrets, depth: 1))", secrets: secrets, to: &lines)
        } else {
            append("choice=none", secrets: secrets, to: &lines)
        }
        append(configurationLine(raw: configurationValue, decoded: configuration, secrets: secrets), secrets: secrets, to: &lines)
        let files = choice?["Files"]
        append("files \(fileSummary(files))", secrets: secrets, to: &lines)
        append("legacy=\(shownLegacy(legacyFileName, secrets: secrets))", secrets: secrets, to: &lines)
        if let content {
            append("content=\(describe(content, secrets: secrets, depth: 2))", secrets: secrets, to: &lines)
        } else {
            append("content=none", secrets: secrets, to: &lines)
        }
        let scope = desktop ?? entry ?? [:]
        appendEncoded(in: scope, secrets: secrets, probe: probe, to: &lines)
        appendAssets(in: scope, secrets: secrets, probe: probe, to: &lines)
        appendFileNotes(in: scope, secrets: secrets, probe: probe, to: &lines)
        return lines
    }

    private static func appendAbsent(legacyFileName: String, secrets: [String], to lines: inout [String]) {
        append("provider=none", secrets: secrets, to: &lines)
        append("entryKeys=none", secrets: secrets, to: &lines)
        append("choice=none", secrets: secrets, to: &lines)
        append("configuration=none", secrets: secrets, to: &lines)
        append("files count=0 extensions=none", secrets: secrets, to: &lines)
        append("legacy=\(shownLegacy(legacyFileName, secrets: secrets))", secrets: secrets, to: &lines)
        append("content=none", secrets: secrets, to: &lines)
        append("encoded=none", secrets: secrets, to: &lines)
        append("asset=none", secrets: secrets, to: &lines)
        append("madesktop=none", secrets: secrets, to: &lines)
        append("heic=none", secrets: secrets, to: &lines)
    }

    private static func append(_ body: String, secrets: [String], to lines: inout [String]) {
        for piece in body.split(separator: "\n", omittingEmptySubsequences: false) {
            appendOne(String(piece), secrets: secrets, to: &lines)
        }
    }

    private static func appendOne(_ body: String, secrets: [String], to lines: inout [String]) {
        guard !body.isEmpty else { return }
        var text = body.hasPrefix("wallpaper-diag ") ? body : "wallpaper-diag \(body)"
        let lowered = text.lowercased()
        for token in secrets {
            let needle = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if needle.count >= 8, lowered.contains(needle) {
                lines.append("wallpaper-diag omitted")
                return
            }
        }
        if text.contains("/") || text.contains("\\") || text.contains("~") {
            lines.append("wallpaper-diag omitted")
            return
        }
        if text.count > 700 {
            text = String(text.prefix(697)) + "..."
        }
        lines.append(text)
    }

    private static func shownProvider(_ provider: String?, secrets: [String]) -> String {
        guard let provider, !provider.isEmpty else { return "none" }
        return WallpaperDiagnosticText.reveal(provider, secrets: secrets) ?? "omitted"
    }

    private static func shownLegacy(_ name: String, secrets: [String]) -> String {
        if name.isEmpty || name == "none" { return "none" }
        return WallpaperDiagnosticText.reveal(name, secrets: secrets) ?? "omitted"
    }

    private static func keyList(_ entry: [String: Any]?, secrets: [String]) -> String {
        guard let entry else { return "none" }
        let names = entry.keys.compactMap { WallpaperDiagnosticText.reveal($0, secrets: secrets) }.sorted()
        return names.isEmpty ? "none" : names.joined(separator: ",")
    }

    private static func configurationLine(raw: Any?, decoded: [String: Any]?, secrets: [String]) -> String {
        if let decoded {
            return "configuration=\(describe(decoded, secrets: secrets, depth: 5))"
        }
        if let data = data(of: raw) {
            return "configuration bytes=\(data.count) kind=\(WallpaperDiagnosticDataKind.detect(data).rawValue)"
        }
        if raw != nil {
            return "configuration=\(describe(raw as Any, secrets: secrets, depth: 2))"
        }
        return "configuration=none"
    }

    private static func fileSummary(_ files: Any?) -> String {
        let count: Int
        if files == nil {
            count = 0
        } else if let list = elements(files) {
            count = list.count
        } else {
            count = 1
        }
        var extensions: Set<String> = []
        collectExtensions(in: files, into: &extensions)
        let listed = extensions.sorted().joined(separator: ",")
        return "count=\(count) extensions=\(listed.isEmpty ? "none" : listed)"
    }

    private static func collectExtensions(in value: Any?, into extensions: inout Set<String>) {
        guard let value else { return }
        if let text = string(value), let ext = fileExtension(of: text) {
            extensions.insert(ext)
            return
        }
        if let dict = dictionary(value) {
            for child in dict.values { collectExtensions(in: child, into: &extensions) }
            return
        }
        if let list = elements(value) {
            for child in list { collectExtensions(in: child, into: &extensions) }
        }
    }

    private static func appendEncoded(
        in scope: [String: Any],
        secrets: [String],
        probe: WallpaperDiagnosticProbe,
        to lines: inout [String]
    ) {
        var found: [Any] = []
        collectValues(named: "EncodedOptionValues", in: scope, depth: 0, into: &found)
        guard !found.isEmpty else {
            append("encoded=none", secrets: secrets, to: &lines)
            return
        }
        for (index, value) in found.enumerated() {
            let prefix = found.count == 1 ? "encoded" : "encoded#\(index + 1)"
            appendEncodedValue(value, prefix: prefix, secrets: secrets, probe: probe, to: &lines)
        }
    }

    private static func appendEncodedValue(
        _ value: Any,
        prefix: String,
        secrets: [String],
        probe: WallpaperDiagnosticProbe,
        to lines: inout [String]
    ) {
        if let data = blob(from: value) {
            let kind = WallpaperDiagnosticDataKind.detect(data)
            append("\(prefix) bytes=\(data.count) kind=\(kind.rawValue)", secrets: secrets, to: &lines)
            if let object = propertyList(data) {
                append("\(prefix) tree=\(describe(object, secrets: secrets, depth: 6))", secrets: secrets, to: &lines)
            } else if kind == .json, let object = jsonObject(data) {
                append("\(prefix) tree=\(describe(object, secrets: secrets, depth: 6))", secrets: secrets, to: &lines)
            }
            if kind == .archiver {
                append(archiveLine(prefix: prefix, data: data, secrets: secrets, probe: probe), secrets: secrets, to: &lines)
            }
            return
        }
        append("\(prefix) tree=\(describe(value, secrets: secrets, depth: 5))", secrets: secrets, to: &lines)
    }

    private static func archiveLine(
        prefix: String,
        data: Data,
        secrets: [String],
        probe: WallpaperDiagnosticProbe
    ) -> String {
        guard let summary = probe.unarchive(data) else { return "\(prefix) classes=failed" }
        let names = summary.classNames.compactMap { WallpaperDiagnosticText.reveal($0, secrets: secrets) }.sorted()
        let classList = names.isEmpty ? "none" : names.joined(separator: ",")
        let numbers = summary.components.prefix(24).filter(\.isFinite).map(formatNumber)
        if numbers.isEmpty { return "\(prefix) classes=\(classList)" }
        return "\(prefix) classes=\(classList) components=\(numbers.joined(separator: ","))"
    }

    private static func appendAssets(
        in scope: [String: Any],
        secrets: [String],
        probe: WallpaperDiagnosticProbe,
        to lines: inout [String]
    ) {
        let identifiers = assetIdentifiers(in: scope)
        guard !identifiers.isEmpty else {
            append("asset=none", secrets: secrets, to: &lines)
            return
        }
        let catalog = loadCatalog(probe: probe)
        for identifier in identifiers {
            let shown = WallpaperDiagnosticText.reveal(identifier, secrets: secrets)
            let idPart = shown.map { " id=\($0)" } ?? ""
            let entry = catalog.object.flatMap { findEntry(in: $0, id: identifier, depth: 0) }
            let contains = entry != nil || catalog.object.map { containsIdentifier(identifier, in: $0, depth: 0) } == true
            let media = entry.map { mediaPaths(in: $0) } ?? (images: [], movies: [])
            let snapshot = media.images.contains { readableFile($0, probe: probe) }
            let movie = media.movies.contains { readableFile($0, probe: probe) }
            append(
                "asset\(idPart) entriesExists=\(catalog.exists) entriesReadable=\(catalog.readable) containsID=\(contains) snapshotReadable=\(snapshot) movReadable=\(movie)",
                secrets: secrets,
                to: &lines
            )
            if let entry {
                append("asset entry=\(describe(entry, secrets: secrets, depth: 5))", secrets: secrets, to: &lines)
            } else if catalog.readable && catalog.object == nil {
                append("asset entry=unavailable", secrets: secrets, to: &lines)
            } else {
                append("asset entry=none", secrets: secrets, to: &lines)
            }
        }
    }

    private struct Catalog {
        var exists: Bool
        var readable: Bool
        var object: Any?
    }

    private static func loadCatalog(probe: WallpaperDiagnosticProbe) -> Catalog {
        guard allowsFileAccess(to: entriesJSONPath) else {
            return Catalog(exists: false, readable: false, object: nil)
        }
        let looked = probe.status(entriesJSONPath)
        if looked.refused { return Catalog(exists: false, readable: false, object: nil) }
        guard looked.readable, let data = probe.read(entriesJSONPath) else {
            return Catalog(exists: looked.exists, readable: false, object: nil)
        }
        return Catalog(exists: true, readable: true, object: jsonObject(data))
    }

    private static func readableFile(_ path: String, probe: WallpaperDiagnosticProbe) -> Bool {
        guard allowsFileAccess(to: path) else { return false }
        let looked = probe.status(path)
        return looked.readable && !looked.refused
    }

    private static func appendFileNotes(
        in scope: [String: Any],
        secrets: [String],
        probe: WallpaperDiagnosticProbe,
        to lines: inout [String]
    ) {
        var refs: [FileRef] = []
        collectFileRefs(in: scope, into: &refs, depth: 0)
        let desktops = unique(refs.filter { $0.ext == "madesktop" })
        let pictures = unique(refs.filter { $0.ext == "heic" })
        let readableDesktops = desktops.filter { !$0.place.isProtected }.sorted { $0.path < $1.path }
        let skippedDesktopPlaces = Array(Set(desktops.filter(\.place.isProtected).map(\.place.rawValue))).sorted()
        if readableDesktops.isEmpty && skippedDesktopPlaces.isEmpty {
            append("madesktop=none", secrets: secrets, to: &lines)
        } else {
            for ref in readableDesktops {
                append(madesktopLine(ref, secrets: secrets, probe: probe), secrets: secrets, to: &lines)
            }
            for place in skippedDesktopPlaces {
                append("madesktop skipped=protected place=\(place)", secrets: secrets, to: &lines)
            }
        }
        if pictures.isEmpty {
            append("heic=none", secrets: secrets, to: &lines)
        } else {
            var skippedPlaces: [String] = []
            var readable: [FileRef] = []
            for ref in pictures {
                if ref.place.isProtected {
                    if !skippedPlaces.contains(ref.place.rawValue) { skippedPlaces.append(ref.place.rawValue) }
                } else {
                    readable.append(ref)
                }
            }
            for ref in readable.sorted(by: { $0.path < $1.path }) {
                append(heicLine(ref, probe: probe), secrets: secrets, to: &lines)
            }
            for place in skippedPlaces.sorted() {
                append("heic skipped=protected place=\(place)", secrets: secrets, to: &lines)
            }
        }
    }

    private static func madesktopLine(_ ref: FileRef, secrets: [String], probe: WallpaperDiagnosticProbe) -> String {
        if ref.place.isProtected { return "madesktop skipped=protected place=\(ref.place.rawValue)" }
        guard allowsFileAccess(to: ref.path) else { return "madesktop skipped=protected place=\(ref.place.rawValue)" }
        let looked = probe.status(ref.path)
        if looked.refused { return "madesktop skipped=protected" }
        guard looked.readable, let data = probe.read(ref.path) else { return "madesktop readable=false" }
        guard let object = propertyList(data) else {
            return "madesktop bytes=\(data.count) kind=\(WallpaperDiagnosticDataKind.detect(data).rawValue)"
        }
        return "madesktop=\(describe(object, secrets: secrets, depth: 5))"
    }

    private static func heicLine(_ ref: FileRef, probe: WallpaperDiagnosticProbe) -> String {
        guard allowsFileAccess(to: ref.path) else { return "heic skipped=protected place=\(ref.place.rawValue)" }
        let looked = probe.status(ref.path)
        if looked.refused { return "heic skipped=protected" }
        guard looked.readable, let info = probe.heic(ref.path) else { return "heic readable=false" }
        return "heic h24=\(info.h24) solar=\(info.solar) apr=\(info.apr) frames=\(info.frames)"
    }

    private struct FileRef {
        var path: String
        var ext: String
        var place: WallpaperPathPlace
    }

    private static func unique(_ refs: [FileRef]) -> [FileRef] {
        var seen: Set<String> = []
        var result: [FileRef] = []
        for ref in refs where seen.insert(ref.path).inserted {
            result.append(ref)
        }
        return result
    }

    private static func collectFileRefs(in value: Any, into refs: inout [FileRef], depth: Int) {
        if depth > 8 { return }
        if let data = data(of: value), let object = propertyList(data) {
            collectFileRefs(in: object, into: &refs, depth: depth + 1)
            return
        }
        if let text = string(value) {
            if let ref = fileRef(from: text) { refs.append(ref) }
            return
        }
        if let dict = dictionary(value) {
            for child in dict.values { collectFileRefs(in: child, into: &refs, depth: depth + 1) }
            return
        }
        if let list = elements(value) {
            for child in list { collectFileRefs(in: child, into: &refs, depth: depth + 1) }
        }
    }

    private static func fileRef(from text: String) -> FileRef? {
        guard text.contains("/") || text.lowercased().hasPrefix("file:") else { return nil }
        guard !hasRemoteScheme(text) else { return nil }
        guard let ext = fileExtension(of: text), ext == "heic" || ext == "madesktop" else { return nil }
        let path = WallpaperPathPlace.normalized(text)
        guard path.hasPrefix("/") else { return nil }
        return FileRef(path: path, ext: ext, place: WallpaperPathPlace.classify(path))
    }

    private static func select(store: [String: Any], displayUUID: String?) -> [String: Any]? {
        let display = displayUUID.flatMap { uuid in
            dictionary(store["Displays"]).flatMap { displayEntry($0, uuid: uuid) }
        }
        let all = dictionary(store["AllSpacesAndDisplays"])
        let system = dictionary(store["SystemDefault"])
        for candidate in [display, all, system] {
            if let candidate, provider(in: candidate) != nil { return candidate }
        }
        return display ?? all ?? system
    }

    private static func firstChoice(in content: [String: Any]?) -> [String: Any]? {
        guard let content, let list = elements(content["Choices"]), let first = list.first else { return nil }
        return dictionary(first)
    }

    private static func provider(in entry: [String: Any]) -> String? {
        guard let desktop = dictionary(entry["Desktop"]),
              let content = dictionary(desktop["Content"]),
              let first = elements(content["Choices"])?.first,
              let choice = dictionary(first),
              let provider = string(choice["Provider"]),
              !provider.isEmpty else { return nil }
        return provider
    }

    private static func displayEntry(_ displays: [String: Any], uuid: String) -> [String: Any]? {
        let wanted = uuid.lowercased()
        guard let match = displays.first(where: { $0.key.lowercased() == wanted }) else { return nil }
        return dictionary(match.value)
    }

    private static func assetIdentifiers(in value: Any) -> [String] {
        var found: [String] = []
        collectAssetIdentifiers(in: value, depth: 0, into: &found)
        return found
    }

    private static func collectAssetIdentifiers(in value: Any, depth: Int, into found: inout [String]) {
        if depth > 8 { return }
        if let data = data(of: value), let object = propertyList(data) {
            collectAssetIdentifiers(in: object, depth: depth + 1, into: &found)
            return
        }
        if let dict = dictionary(value) {
            for (key, child) in dict {
                if isAssetKey(key), let text = string(child) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if isUsableIdentifier(trimmed), !found.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        found.append(trimmed)
                    }
                }
                collectAssetIdentifiers(in: child, depth: depth + 1, into: &found)
            }
            return
        }
        if let list = elements(value) {
            for child in list { collectAssetIdentifiers(in: child, depth: depth + 1, into: &found) }
        }
    }

    private static func isAssetKey(_ key: String) -> Bool {
        switch key.lowercased() {
        case "assetid", "assetidentifier", "assetuuid":
            return true
        default:
            return false
        }
    }

    private static func isUsableIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.count < 128 && !text.contains("/") && !text.contains("\\") && !text.contains("~") && !text.contains(" ")
    }

    private static func collectValues(named wanted: String, in value: Any, depth: Int, into found: inout [Any]) {
        if depth > 8 { return }
        if let data = data(of: value), let object = propertyList(data) {
            collectValues(named: wanted, in: object, depth: depth + 1, into: &found)
            return
        }
        if let dict = dictionary(value) {
            for (key, child) in dict {
                if key.caseInsensitiveCompare(wanted) == .orderedSame { found.append(child) }
                collectValues(named: wanted, in: child, depth: depth + 1, into: &found)
            }
            return
        }
        if let list = elements(value) {
            for child in list { collectValues(named: wanted, in: child, depth: depth + 1, into: &found) }
        }
    }

    private static func containsIdentifier(_ id: String, in value: Any, depth: Int) -> Bool {
        if depth > 12 { return false }
        if let text = string(value) { return text.caseInsensitiveCompare(id) == .orderedSame }
        if let dict = dictionary(value) {
            for (key, child) in dict {
                if key.caseInsensitiveCompare(id) == .orderedSame { return true }
                if containsIdentifier(id, in: child, depth: depth + 1) { return true }
            }
            return false
        }
        if let list = elements(value) {
            return list.contains { containsIdentifier(id, in: $0, depth: depth + 1) }
        }
        return false
    }

    private static func findEntry(in value: Any, id: String, depth: Int) -> [String: Any]? {
        if depth > 12 { return nil }
        if let list = elements(value) {
            for item in list {
                if let found = findEntry(in: item, id: id, depth: depth + 1) { return found }
            }
            return nil
        }
        guard let dict = dictionary(value) else { return nil }
        var deeper: [String: Any]?
        var direct = false
        for (key, child) in dict {
            if key.caseInsensitiveCompare(id) == .orderedSame { direct = true }
            if let text = string(child), text.caseInsensitiveCompare(id) == .orderedSame { direct = true }
            if deeper == nil, let found = findEntry(in: child, id: id, depth: depth + 1) { deeper = found }
        }
        return deeper ?? (direct ? dict : nil)
    }

    private static func mediaPaths(in entry: [String: Any]) -> (images: [String], movies: [String]) {
        var images: [String] = []
        var movies: [String] = []
        collectMedia(in: entry, images: &images, movies: &movies, depth: 0)
        return (images, movies)
    }

    private static func collectMedia(in value: Any, images: inout [String], movies: inout [String], depth: Int) {
        if depth > 8 { return }
        if let text = string(value), let media = localMedia(text) {
            if media.ext == "mov" { movies.append(media.path) } else { images.append(media.path) }
            return
        }
        if let dict = dictionary(value) {
            for child in dict.values { collectMedia(in: child, images: &images, movies: &movies, depth: depth + 1) }
            return
        }
        if let list = elements(value) {
            for child in list { collectMedia(in: child, images: &images, movies: &movies, depth: depth + 1) }
        }
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]

    private static func localMedia(_ text: String) -> (path: String, ext: String)? {
        guard !hasRemoteScheme(text) else { return nil }
        guard let ext = fileExtension(of: text) else { return nil }
        let isImage = imageExtensions.contains(ext)
        guard isImage || ext == "mov" else { return nil }
        if text.hasPrefix("/") || text.lowercased().hasPrefix("file:") {
            let path = WallpaperPathPlace.normalized(text)
            guard allowsFileAccess(to: path) else { return nil }
            return (path, ext)
        }
        guard !text.contains("~"), !text.contains("..") else { return nil }
        let combined = customerDirectory + "/" + text
        guard allowsFileAccess(to: combined), combined.hasPrefix(customerDirectory + "/") else { return nil }
        return (WallpaperPathPlace.normalized(combined), ext)
    }

    private static func hasRemoteScheme(_ text: String) -> Bool {
        guard let range = text.range(of: "://") else { return false }
        return !text[..<range.lowerBound].lowercased().hasSuffix("file") && !text.lowercased().hasPrefix("file:")
    }

    private static let knownExtensions: Set<String> = [
        "heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "webp", "gif", "bmp", "mov", "madesktop", "m4v", "mp4"
    ]

    private static func fileExtension(of text: String) -> String? {
        let leaf: String
        if text.lowercased().hasPrefix("file:") || text.contains("/") {
            leaf = (WallpaperPathPlace.normalized(text) as NSString).lastPathComponent
        } else {
            leaf = (text as NSString).lastPathComponent
        }
        let ext = (leaf as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, ext.count <= 16, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        if text.contains("/") || text.lowercased().hasPrefix("file:") || knownExtensions.contains(ext) { return ext }
        return nil
    }

    private static func blob(from value: Any) -> Data? {
        if let data = data(of: value) { return data }
        guard let text = string(value) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16,
              let data = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
              data.count >= 8 else { return nil }
        return data
    }

    private static func decodedDictionary(_ value: Any?) -> [String: Any]? {
        if let value, let dict = dictionary(value) { return dict }
        return WallpaperStoreIndex.decodePropertyList(value)
    }

    private static func propertyList(_ data: Data) -> Any? {
        guard !data.isEmpty else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    private static func jsonObject(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [])
    }

    private static func describe(_ value: Any, secrets: [String], depth: Int) -> String {
        var budget = 250
        return describe(value, secrets: secrets, depth: depth, budget: &budget)
    }

    private static func describe(_ value: Any, secrets: [String], depth: Int, budget: inout Int) -> String {
        guard budget > 0 else { return "..." }
        budget -= 1
        if let text = string(value) {
            guard let shown = WallpaperDiagnosticText.reveal(text, secrets: secrets) else { return "String" }
            return "String(\(shown))"
        }
        if let data = data(of: value) { return "Data(\(data.count)bytes)" }
        if value is Date || value is NSDate { return "Date" }
        if let dict = dictionary(value) {
            guard depth > 0 else { return "Dict" }
            let body = dict.keys.sorted().prefix(12).compactMap { key -> String? in
                guard let name = WallpaperDiagnosticText.reveal(key, secrets: secrets) else { return nil }
                return "\(name)=\(describe(dict[key] ?? NSNull(), secrets: secrets, depth: depth - 1, budget: &budget))"
            }.joined(separator: ",")
            return "Dict(\(body))"
        }
        if let list = elements(value) {
            if let numbers = numberList(list) { return numbers }
            guard depth > 0, !list.isEmpty else { return "Array(\(list.count))" }
            let shown = list.prefix(4).map { describe($0, secrets: secrets, depth: depth - 1, budget: &budget) }
            if list.count > shown.count { return "Array(\(shown.joined(separator: ",")),...\(list.count))" }
            return "Array(\(shown.joined(separator: ",")))"
        }
        if let token = numberToken(value) { return token }
        if value is NSNull { return "Null" }
        return "Other"
    }

    private static func numberList(_ list: [Any]) -> String? {
        guard !list.isEmpty else { return nil }
        var numbers: [Double] = []
        for item in list {
            guard let number = plainNumber(item) else { return nil }
            numbers.append(number)
        }
        let text = numbers.prefix(6).map(formatNumber).joined(separator: ",")
        return "[\(text)]"
    }

    private static func numberToken(_ value: Any) -> String? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return "Bool(\(number.boolValue))" }
            return numericToken(number.doubleValue, integral: number.intValue)
        }
        if let bool = value as? Bool { return "Bool(\(bool))" }
        if let int = value as? Int { return "Int(\(int))" }
        if let double = value as? Double { return numericToken(double, integral: Int(double)) }
        return nil
    }

    private static func numericToken(_ double: Double, integral: Int) -> String {
        guard double.isFinite else { return "Number" }
        if double.rounded() == double, abs(double) < 1_000_000_000 { return "Int(\(integral))" }
        return "Double(\(formatNumber(double)))"
    }

    private static func plainNumber(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let double = number.doubleValue
            return double.isFinite ? double : nil
        }
        if value is Bool { return nil }
        if let int = value as? Int { return Double(int) }
        if let double = value as? Double, double.isFinite { return double }
        return nil
    }

    private static func formatNumber(_ value: Double) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] { return dict }
        guard let dict = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for key in dict.allKeys {
            guard let name = key as? String else { continue }
            result[name] = dict[key]
        }
        return result
    }

    private static func elements(_ value: Any?) -> [Any]? {
        guard let value else { return nil }
        if let list = value as? [Any] { return list }
        if let list = value as? [[String: Any]] { return list.map { $0 as Any } }
        if let list = value as? [String] { return list.map { $0 as Any } }
        if let list = value as? [Double] { return list.map { $0 as Any } }
        if let list = value as? [Int] { return list.map { $0 as Any } }
        if let list = value as? NSArray { return list.map { $0 as Any } }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let text = value as? NSString { return text as String }
        return nil
    }

    private static func data(of value: Any?) -> Data? {
        if let data = value as? Data { return data }
        if let data = value as? NSData { return data as Data }
        return nil
    }
}
