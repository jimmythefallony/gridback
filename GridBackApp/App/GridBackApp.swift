import AppKit
import SwiftUI

@main
struct GridBackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = GridBackModel.shared

    var body: some Scene {
        MenuBarExtra {
            Button(String(localized: "Open GridBack")) {
                model.showOverlay()
            }
            Button(String(localized: "Settings…")) {
                model.showSettings()
            }
            Divider()
            Button(model.shortcutMenuTitle) {}
                .disabled(true)
            if let failure = model.hotkeyFailure {
                Button(failure) {}
                    .disabled(true)
            }
            if let warning = model.persistenceWarning {
                Button(warning) {}
                    .disabled(true)
            }
            Divider()
            Button(String(localized: "Quit GridBack")) {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "square.grid.3x3.fill")
                .accessibilityLabel(String(localized: "GridBack"))
        }
    }
}
