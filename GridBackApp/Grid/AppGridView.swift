import AppKit
import GridBackCore
import SwiftUI

struct AppGridView: View {
    @ObservedObject var model: GridBackModel
    var layout: LaunchGridLayout
    var ids: [String]
    var hiddenID: String?
    var blockLaunch: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if hiddenID == nil {
                        model.hideOverlay()
                    }
                }
            ForEach(Array(ids.enumerated()), id: \.element) { slot, id in
                if id != hiddenID {
                    AppIconButton(
                        title: model.appsByID[id]?.displayName ?? id,
                        image: model.iconImages[id],
                        iconSide: layout.iconSide,
                        labelWidth: max(layout.hitWidth - 12, layout.iconSide)
                    ) {
                        guard !blockLaunch else { return }
                        model.launch(id: id)
                    }
                    .position(
                        x: layout.originX + layout.columnCenter(slot),
                        y: layout.rowCenter(slot)
                    )
                }
            }
        }
        .frame(width: layout.pageWidth, height: layout.gridHeight)
        .animation(.easeInOut(duration: 0.16), value: ids)
    }
}

struct SearchPill: View {
    @Binding var query: String
    @FocusState var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.white.opacity(0.65))
            SearchPillField(text: $query, isFocused: $isFocused)
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 18)
        .frame(width: 280, height: 40)
        .background(Color.white.opacity(0.16), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .accessibilityLabel(String(localized: "Search"))
        .accessibilityValue(query)
    }
}

/// The system text field draws its placeholder in dark grey and its caret in
/// the accent blue. This field keeps the same typing behavior with white text.
private struct SearchPillField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    func makeNSView(context: Context) -> SearchPillTextField {
        let field = SearchPillTextField(string: "")
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = SearchPillTextField.font
        field.textColor = .white
        field.placeholderAttributedString = SearchPillTextField.placeholder
        field.delegate = context.coordinator
        field.setAccessibilityLabel(String(localized: "Search"))
        return field
    }

    func updateNSView(_ field: SearchPillTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = isFocused
        if field.stringValue != text {
            context.coordinator.isUpdatingFromModel = true
            field.stringValue = text
            context.coordinator.isUpdatingFromModel = false
        }
        field.textColor = .white
        field.placeholderAttributedString = SearchPillTextField.placeholder
        field.paintCaret()
        guard isFocused.wrappedValue, let window = field.window else { return }
        let editor = field.currentEditor()
        guard window.firstResponder !== field, window.firstResponder !== editor else { return }
        DispatchQueue.main.async {
            guard field.window?.firstResponder !== field,
                  field.window?.firstResponder !== field.currentEditor() else { return }
            field.window?.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: FocusState<Bool>.Binding
        var isUpdatingFromModel = false

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding) {
            self.text = text
            self.isFocused = isFocused
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdatingFromModel, let field = notification.object as? NSTextField else { return }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
            (field as? SearchPillTextField)?.paintCaret()
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
            (notification.object as? SearchPillTextField)?.paintCaret()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if field.window?.firstResponder !== field.currentEditor() {
                isFocused.wrappedValue = false
            }
        }
    }
}

private final class SearchPillTextField: NSTextField {
    static let font = NSFont.systemFont(ofSize: 16, weight: .medium)

    static var placeholder: NSAttributedString {
        NSAttributedString(
            string: String(localized: "Search"),
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.65),
                .font: font
            ]
        )
    }

    override var allowsVibrancy: Bool { false }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        paintCaret()
        DispatchQueue.main.async { [weak self] in self?.paintCaret() }
        return accepted
    }

    func paintCaret() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = .white
        editor.textColor = .white
    }
}
