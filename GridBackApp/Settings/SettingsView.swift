import GridBackCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: GridBackModel
    @ObservedObject var loginItem: LoginItemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Keyboard shortcut"))
                .font(.headline)
            Text(model.shortcut.displayString)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .accessibilityLabel(String(localized: "Current shortcut \(model.shortcut.displayString)"))

            Text(model.shortcutStatus ?? String(localized: "The starting shortcut is Control-Option-G. Include Control, Option, or Command."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(model.isRecordingShortcut ? String(localized: "Press a shortcut…") : String(localized: "Change Shortcut")) {
                    model.beginShortcutRecording()
                }
                .disabled(model.isRecordingShortcut)
                Button(String(localized: "Reset to Default")) {
                    model.resetShortcutToDefault()
                }
            }

            if let failure = model.hotkeyFailure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(String(localized: "GridBack listens for this shortcut while it is running in the menu bar. If a shortcut can't be registered, open the grid from the menu and try a different one."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle(String(localized: "Start GridBack at login"), isOn: Binding(
                get: { loginItem.state.isOn },
                set: { loginItem.setEnabled($0) }
            ))
            .id(loginItem.revision)

            if let failure = loginItem.state.failure {
                Text(failureMessage(failure))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if loginItem.state.needsApproval {
                Text(String(localized: "macOS needs your approval in Login Items before GridBack will open at login."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "Open Login Items")) {
                    loginItem.openSystemSettingsLoginItems()
                }
            }

            if loginItem.state.notFound {
                Text(String(localized: "macOS can't use this copy of GridBack for login. Move GridBack into your Applications folder and open that copy, then try again."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, height: 440, alignment: .topLeading)
        .onAppear { loginItem.refresh() }
    }

    private func failureMessage(_ failure: LoginItemFailure) -> String {
        switch failure {
        case .couldNotTurnOn:
            return String(localized: "GridBack couldn't turn on start at login.")
        case .couldNotTurnOff:
            return String(localized: "GridBack couldn't turn off start at login.")
        }
    }
}
