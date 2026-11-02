import Foundation

/// Turns bundle metadata into an `AppRecord`. Display name preference is
/// localized display name, Info.plist display name, localized bundle name,
/// Info.plist bundle name, then the file name. `LSBackgroundOnly` bundles are
/// skipped. Menu-bar apps (`LSUIElement`) are kept.
public enum BundleInfoParser {
    public static func makeRecord(
        infoDictionary: [String: Any],
        localizedDisplayName: String?,
        localizedBundleName: String?,
        bundlePath: String
    ) -> AppRecord? {
        if isBackgroundOnly(infoDictionary) {
            return nil
        }
        let identifier = nonEmpty(string(infoDictionary["CFBundleIdentifier"]))
        let displayName = firstNonEmpty([
            localizedDisplayName,
            string(infoDictionary["CFBundleDisplayName"]),
            localizedBundleName,
            string(infoDictionary["CFBundleName"]),
            fileDisplayName(bundlePath)
        ])
        guard let displayName else { return nil }
        return AppRecord(
            bundleIdentifier: identifier,
            bundlePath: bundlePath,
            displayName: displayName
        )
    }

    public static func isBackgroundOnly(_ info: [String: Any]) -> Bool {
        bool(info["LSBackgroundOnly"])
    }

    public static func fileDisplayName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? url.lastPathComponent : base
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            if let cleaned = nonEmpty(value) {
                return cleaned
            }
        }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func bool(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
