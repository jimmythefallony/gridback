import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: GridBackModel

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
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, height: 280, alignment: .topLeading)
    }
}
