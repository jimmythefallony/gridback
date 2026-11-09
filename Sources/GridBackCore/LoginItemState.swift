import Foundation

/// The four states `SMAppService.Status` can report for this app.
/// The app target translates the system value into this type. The checkbox
/// is on only for `.enabled`.
public enum LoginItemSystemStatus: String, Equatable, Sendable, CaseIterable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum LoginItemFailure: Equatable, Sendable {
    case couldNotTurnOn
    case couldNotTurnOff
}

public struct LoginItemViewState: Equatable, Sendable {
    public var isOn: Bool
    public var needsApproval: Bool
    public var notFound: Bool
    public var failure: LoginItemFailure?

    public init(isOn: Bool, needsApproval: Bool, notFound: Bool, failure: LoginItemFailure?) {
        self.isOn = isOn
        self.needsApproval = needsApproval
        self.notFound = notFound
        self.failure = failure
    }

    /// The checkbox matches the system. Approval and a missing app stay off,
    /// with their own note, so the control does not claim login will open GridBack.
    public static func make(status: LoginItemSystemStatus, failure: LoginItemFailure? = nil) -> LoginItemViewState {
        LoginItemViewState(
            isOn: status == .enabled,
            needsApproval: status == .requiresApproval,
            notFound: status == .notFound,
            failure: failure
        )
    }
}

public protocol LoginItemService: AnyObject {
    func currentStatus() -> LoginItemSystemStatus
    func register() throws
    func unregister() throws
}

/// Reads and changes the login item. Creating it only reads status. It does not register.
public final class LoginItemController {
    private let service: LoginItemService
    public private(set) var state: LoginItemViewState

    public init(service: LoginItemService) {
        self.service = service
        state = .make(status: service.currentStatus())
    }

    public func refresh() {
        state = .make(status: service.currentStatus())
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            state = .make(status: service.currentStatus())
        } catch {
            let status = service.currentStatus()
            state = .make(status: status, failure: Self.failure(afterSetting: enabled, status: status))
        }
    }

    /// A status that already explains the outcome does not also get a generic error.
    static func failure(afterSetting enabled: Bool, status: LoginItemSystemStatus) -> LoginItemFailure? {
        if enabled {
            switch status {
            case .enabled, .requiresApproval, .notFound:
                return nil
            case .notRegistered:
                return .couldNotTurnOn
            }
        }
        return status == .enabled ? .couldNotTurnOff : nil
    }
}
