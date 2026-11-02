import Foundation
import GridBackCore

/// Finds apps in the standard Application folders.
///
/// Roots, in order: `~/Applications`, `/Applications`, `/System/Applications`.
/// The first copy of a bundle identifier wins, so a personal copy beats the
/// system copy. See `CatalogPathRules` for what is skipped.
struct AppCatalog {
    var fileManager: FileManager = .default

    func roots() -> [URL] {
        [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    }

    func scan() -> [AppRecord] {
        var records: [AppRecord] = []
        var seen = Set<String>()
        for root in roots() where fileManager.fileExists(atPath: root.path) {
            scan(directory: root, depth: 0, into: &records, seen: &seen)
        }
        return records
    }

    private func scan(directory: URL, depth: Int, into records: inout [AppRecord], seen: inout Set<String>) {
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for url in children {
            let name = url.lastPathComponent
            let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            if CatalogPathRules.isAppBundleName(name) {
                let resolved = url.resolvingSymlinksInPath()
                guard isDirectory(resolved), CatalogPathRules.shouldIncludeApp(path: resolved.path) else {
                    continue
                }
                guard let record = makeRecord(at: resolved) else { continue }
                guard seen.insert(record.id).inserted else { continue }
                records.append(record)
                continue
            }
            if isLink {
                continue
            }
            guard CatalogPathRules.shouldDescend(name: name, depth: depth), isDirectory(url) else {
                continue
            }
            scan(directory: url, depth: depth + 1, into: &records, seen: &seen)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func makeRecord(at url: URL) -> AppRecord? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let localized = bundle?.localizedInfoDictionary
        return BundleInfoParser.makeRecord(
            infoDictionary: info,
            localizedDisplayName: localized?["CFBundleDisplayName"] as? String,
            localizedBundleName: localized?["CFBundleName"] as? String,
            bundlePath: url.path
        )
    }
}
