import Foundation

/// Which paths count as apps the person can launch.
///
/// Included: `.app` bundles directly in the scanned folders, plus apps nested
/// a few folder levels down (for example `/Applications/Utilities/Terminal.app`).
///
/// Excluded: anything inside another `.app` (helpers and nested bundles),
/// hidden names, and other package types we do not descend into (frameworks,
/// plug-ins, preference panes, and similar).
public enum CatalogPathRules {
    /// How many directory levels below a root we still enter.
    /// 0 is the root itself. 3 reaches `/Applications/Group/Tools/Extra/App.app`.
    public static let maxScanDepth = 3

    public static let opaquePackageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "kext", "workflow",
        "prefpane", "qlgenerator", "saver", "mdimporter", "appex", "xpc"
    ]

    public static func isHiddenName(_ name: String) -> Bool {
        name.hasPrefix(".")
    }

    public static func isAppBundleName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".app") && lower.count > ".app".count
    }

    public static func isInsideAnotherApp(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return false }
        return parts.dropLast().contains { $0.lowercased().hasSuffix(".app") }
    }

    public static func shouldIncludeApp(path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if isHiddenName(name) || !isAppBundleName(name) {
            return false
        }
        return !isInsideAnotherApp(path)
    }

    /// `depth` is the depth of the directory being listed. Children of an
    /// accepted directory are visible even when we will not descend further.
    public static func shouldDescend(name: String, depth: Int, maxDepth: Int = maxScanDepth) -> Bool {
        if depth >= maxDepth || isHiddenName(name) || isAppBundleName(name) {
            return false
        }
        let ext = (name as NSString).pathExtension.lowercased()
        return !opaquePackageExtensions.contains(ext)
    }
}
