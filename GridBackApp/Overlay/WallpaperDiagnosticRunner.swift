import AppKit
import Darwin
import Foundation
import GridBackCore
import os

/// Reads the wallpaper store off the main thread and writes a private-safe description.
/// The picture queue is not used, so this does not delay the grid opening.
enum WallpaperDiagnosticRunner {
    private static let queue = DispatchQueue(
        label: "com.jimmythefallony.GridBack.wallpaper-diag",
        qos: .utility
    )
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jimmythefallony.GridBack",
        category: "wallpaper-diag"
    )
    private static let probe = WallpaperDiagnosticProbe(
        status: { WallpaperDiagnosticAccess.status(of: $0) },
        read: { WallpaperDiagnosticAccess.read(path: $0) },
        heic: { WallpaperDiagnosticAccess.heic(at: $0) },
        unarchive: { WallpaperDiagnosticAccess.unarchive($0) }
    )

    static func schedule(displayUUID: String?, legacyFileName: String) {
        let uuid = displayUUID
        let legacy = legacyFileName
        queue.async {
            let store = WallpaperStoreReader.read()
            let lines = WallpaperDiagnostics.lines(
                store: store,
                displayUUID: uuid,
                legacyFileName: legacy,
                secrets: secrets(store: store, displayUUID: uuid),
                probe: probe
            )
            for line in lines {
                log.debug("\(line, privacy: .public)")
                mirrorToDebugConsole(line)
            }
        }
    }

    /// Debug-level Logger text is kept out of the Xcode console unless a logging
    /// profile enables it. A Debug build, which is what Xcode runs, also writes
    /// the same line to the debug console.
    private static func mirrorToDebugConsole(_ line: String) {
        #if DEBUG
        line.withCString { _ = fputs($0, stderr) }
        _ = fputs("\n", stderr)
        #endif
    }

    private static func secrets(store: [String: Any]?, displayUUID: String?) -> [String] {
        var tokens: [String] = []
        if let displayUUID, !displayUUID.isEmpty { tokens.append(displayUUID) }
        if let displays = store?["Displays"] as? [String: Any] {
            tokens.append(contentsOf: displays.keys)
        }
        let user = NSUserName()
        if !user.isEmpty { tokens.append(user) }
        let home = FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
        if !home.isEmpty { tokens.append(home) }
        let host = ProcessInfo.processInfo.hostName
        if !host.isEmpty { tokens.append(host) }
        if let short = host.split(separator: ".").first {
            let name = String(short)
            if name.count >= 4 { tokens.append(name) }
        }
        if let local = Host.current().localizedName, !local.isEmpty { tokens.append(local) }
        return tokens
    }
}

/// Opens a file only after its path is known to be outside a protected folder.
/// Symbolic links are read as text. A link into a protected folder is not opened.
enum WallpaperDiagnosticAccess {
    static func status(of path: String) -> WallpaperDiagnosticFileStatus {
        guard let opened = resolve(path) else {
            return WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: true)
        }
        return inspect(opened)
    }

    static func read(path: String) -> Data? {
        let limit = path == WallpaperDiagnostics.entriesJSONPath ? 8_000_000 : 1_000_000
        guard let opened = resolve(path) else { return nil }
        return opened.withCString { cPath -> Data? in
            let fd = open(cPath, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var info = Darwin.stat()
            guard fstat(fd, &info) == 0, (mode_t(info.st_mode) & S_IFMT) == S_IFREG else { return nil }
            let size = Int(info.st_size)
            guard size > 0, size <= limit else { return nil }
            var data = Data(count: size)
            let count = data.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.read(fd, base, size)
            }
            guard count == size else { return nil }
            return data
        }
    }

    static func heic(at path: String) -> WallpaperDiagnosticHEIC? {
        guard let opened = resolve(path) else { return nil }
        let looked = inspect(opened)
        guard looked.readable, !looked.refused else { return nil }
        guard let presence = WallpaperFileMetadata.presence(at: URL(fileURLWithPath: opened)) else { return nil }
        return WallpaperDiagnosticHEIC(
            h24: presence.h24,
            solar: presence.solar,
            apr: presence.apr,
            frames: presence.frames
        )
    }

    /// Secure decode only. Classes outside the allowed set fail the decode.
    static func unarchive(_ data: Data) -> WallpaperDiagnosticArchive? {
        guard data.count <= 1_000_000 else { return nil }
        let allowed: [AnyClass] = [
            NSColor.self,
            NSDictionary.self,
            NSArray.self,
            NSString.self,
            NSNumber.self,
            NSData.self
        ]
        guard let root = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowed, from: data) else {
            return nil
        }
        var names = Set<String>()
        var components: [Double] = []
        collect(root, names: &names, components: &components)
        return WallpaperDiagnosticArchive(classNames: Array(names), components: components)
    }

    private static func collect(_ value: Any, names: inout Set<String>, components: inout [Double]) {
        if let color = value as? NSColor {
            names.insert("NSColor")
            if components.count < 24, let rgb = color.usingColorSpace(.sRGB) {
                components.append(Double(rgb.redComponent))
                components.append(Double(rgb.greenComponent))
                components.append(Double(rgb.blueComponent))
                components.append(Double(rgb.alphaComponent))
            }
            return
        }
        if let dictionary = value as? NSDictionary {
            names.insert("NSDictionary")
            for key in dictionary.allKeys {
                collect(key, names: &names, components: &components)
                if let child = dictionary[key] {
                    collect(child, names: &names, components: &components)
                }
            }
            return
        }
        if let array = value as? NSArray {
            names.insert("NSArray")
            for item in array { collect(item, names: &names, components: &components) }
            return
        }
        if value is NSString {
            names.insert("NSString")
            return
        }
        if value is NSNumber {
            names.insert("NSNumber")
            return
        }
        if value is NSData {
            names.insert("NSData")
            return
        }
    }

    private static func inspect(_ path: String) -> WallpaperDiagnosticFileStatus {
        path.withCString { cPath in
            var info = Darwin.stat()
            guard lstat(cPath, &info) == 0 else {
                return WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: false)
            }
            let kind = mode_t(info.st_mode) & S_IFMT
            if kind == S_IFLNK {
                return WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: true)
            }
            guard kind == S_IFREG else {
                return WallpaperDiagnosticFileStatus(exists: false, readable: false, refused: false)
            }
            return WallpaperDiagnosticFileStatus(exists: true, readable: access(cPath, R_OK) == 0, refused: false)
        }
    }

    /// The final path is a real file, not a link. Nil means the path must not be opened.
    private static func resolve(_ path: String) -> String? {
        var current = WallpaperPathPlace.normalized(path)
        guard WallpaperDiagnostics.allowsFileAccess(to: current) else { return nil }
        for _ in 0..<8 {
            switch link(at: current) {
            case .absent, .plain:
                return current
            case .refuse:
                return nil
            case .target(let target):
                let next = target.hasPrefix("/")
                    ? target
                    : ((current as NSString).deletingLastPathComponent as NSString).appendingPathComponent(target)
                let normalized = WallpaperPathPlace.normalized(next)
                guard WallpaperDiagnostics.allowsFileAccess(to: normalized) else { return nil }
                current = normalized
            }
        }
        return nil
    }

    private enum Link {
        case absent
        case plain
        case refuse
        case target(String)
    }

    private static func link(at path: String) -> Link {
        path.withCString { cPath in
            var info = Darwin.stat()
            guard lstat(cPath, &info) == 0 else { return .absent }
            guard (mode_t(info.st_mode) & S_IFMT) == S_IFLNK else { return .plain }
            var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
            let count = readlink(cPath, &buffer, buffer.count - 1)
            guard count > 0 else { return .refuse }
            buffer[Int(count)] = 0
            return .target(String(cString: buffer))
        }
    }
}
