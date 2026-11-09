import AppKit
import Combine
import GridBackCore

/// Settings-facing login item. Status is read when Settings opens and when
/// the app becomes active. Nothing here polls the event queue.
final class LoginItemModel: ObservableObject {
    @Published private(set) var state: LoginItemViewState
    @Published private(set) var revision = 0

    private let controller: LoginItemController
    private var activeObserver: NSObjectProtocol?

    init(service: LoginItemService) {
        controller = LoginItemController(service: service)
        state = controller.state
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    func refresh() {
        controller.refresh()
        publish()
    }

    func setEnabled(_ enabled: Bool) {
        controller.setEnabled(enabled)
        publish()
    }

    func openSystemSettingsLoginItems() {
        SystemLoginItemService.openSystemSettingsLoginItems()
    }

    private func publish() {
        state = controller.state
        revision += 1
    }
}
