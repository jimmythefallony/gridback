import Foundation

/// Reads and writes `state.json` with an atomic replace so a crash mid-save
/// cannot leave a half-written layout.
public struct PersistenceStore: Sendable {
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public var stateURL: URL {
        directoryURL.appendingPathComponent("state.json")
    }

    public func load() throws -> PersistedState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: stateURL)
        let decoded: PersistedState
        do {
            decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            throw PersistenceError.unreadable(String(describing: error))
        }
        guard decoded.version == PersistedState.currentVersion else {
            throw PersistenceError.unsupportedVersion(decoded.version)
        }
        return decoded.repaired()
    }

    public func save(_ state: PersistedState) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state.repaired())
        let temporaryURL = directoryURL.appendingPathComponent(".state-\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: [.atomic])
        do {
            if FileManager.default.fileExists(atPath: stateURL.path) {
                _ = try FileManager.default.replaceItemAt(stateURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: stateURL)
            }
        } catch {
            if FileManager.default.fileExists(atPath: stateURL.path) {
                try? FileManager.default.removeItem(at: stateURL)
            }
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.moveItem(at: temporaryURL, to: stateURL)
            } else {
                try data.write(to: stateURL, options: [.atomic])
            }
        }
    }

    /// Moves a state file the app could not use, so the next save does not
    /// overwrite the person's previous file.
    public func quarantineStateFile(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        let stamp = Int(now.timeIntervalSince1970)
        let destination = directoryURL.appendingPathComponent("state.json.unreadable-\(stamp)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: stateURL, to: destination)
        return destination
    }
}
