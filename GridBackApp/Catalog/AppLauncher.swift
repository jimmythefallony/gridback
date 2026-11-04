import AppKit
import GridBackCore

enum LaunchFailure: LocalizedError {
    case missingBundle

    var errorDescription: String? {
        switch self {
        case .missingBundle:
            return String(localized: "That app is no longer on this Mac.")
        }
    }
}

/// Opens an app through Launch Services. Never shells out to the binary.
struct AppLauncher {
    func launch(_ record: AppRecord, completion: @escaping (Result<NSRunningApplication?, Error>) -> Void) {
        let url = URL(fileURLWithPath: record.bundlePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            completion(.failure(LaunchFailure.missingBundle))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(application))
            }
        }
    }
}
