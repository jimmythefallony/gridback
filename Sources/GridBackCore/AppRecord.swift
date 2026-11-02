import Foundation

/// One launchable app. `id` is the bundle identifier when the bundle has one,
/// otherwise the absolute bundle path. Layout pages store these ids.
public struct AppRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var bundleIdentifier: String?
    public var bundlePath: String
    public var displayName: String

    public init(bundleIdentifier: String?, bundlePath: String, displayName: String) {
        let trimmedID = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = (trimmedID?.isEmpty == false) ? trimmedID : nil
        self.bundleIdentifier = identifier
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.id = identifier ?? bundlePath
    }
}
