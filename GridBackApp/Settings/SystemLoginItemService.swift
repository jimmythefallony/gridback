import GridBackCore
import ServiceManagement

/// The real login item for this app. `mainApp` launches GridBack at login
/// and does not open the grid; the app only opens the grid from the menu or the shortcut.
final class SystemLoginItemService: LoginItemService {
    func currentStatus() -> LoginItemSystemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notRegistered
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    static func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
