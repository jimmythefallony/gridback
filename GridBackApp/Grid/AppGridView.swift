import AppKit
import GridBackCore
import SwiftUI

struct AppGridView: View {
    @ObservedObject var model: GridBackModel
    var layout: LaunchGridLayout
    var items: [GridBackCore.GridItem]
    var hiddenID: String?
    var hiddenFolderID: String?
    var armedID: String?
    var blockLaunch: Bool
    var displayFolders: [AppFolder]? = nil
    var suppressedAppID: String? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if hiddenID == nil {
                        if model.openFolderID != nil {
                            model.closeFolder()
                        } else {
                            model.hideOverlay()
                        }
                    }
                }
            ForEach(Array(items.enumerated()), id: \.element.id) { slot, item in
                if item.id != hiddenID && item.id != hiddenFolderID {
                    tile(item, slot: slot)
                        .position(
                            x: layout.originX + layout.columnCenter(slot),
                            y: layout.rowCenter(slot)
                        )
                }
            }
        }
        .frame(width: layout.pageWidth, height: layout.gridHeight)
        .animation(.easeInOut(duration: 0.16), value: items)
    }

    @ViewBuilder
    private func tile(_ item: GridBackCore.GridItem, slot: Int) -> some View {
        let armed = item.id == armedID
        switch item {
        case .app(let id):
            AppIconButton(
                title: model.appsByID[id]?.displayName ?? id,
                image: model.iconImages[id],
                iconSide: layout.iconSide,
                labelWidth: max(layout.hitWidth - 12, layout.iconSide)
            ) {
                guard !blockLaunch else { return }
                model.launch(id: id)
            }
            .overlay {
                if armed {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: layout.iconSide + 14, height: layout.iconSide + 14)
                        .offset(y: -(layout.labelHeight + layout.iconLabelGap) / 2)
                }
            }
        case .folder(let id):
            let folder = (displayFolders ?? model.layout.folders).first { $0.id == id } ?? model.layout.folder(id)
            FolderTile(
                name: folder?.name ?? AppFolder.defaultName,
                icons: (folder?.appIDs ?? []).filter { $0 != suppressedAppID }.prefix(9).map { model.iconImages[$0] },
                iconSide: layout.iconSide,
                labelWidth: max(layout.hitWidth - 12, layout.iconSide),
                armed: armed
            ) {
                guard !blockLaunch else { return }
                model.openFolder(id)
            }
        }
    }
}

struct FolderTile: View {
    let name: String
    let icons: [NSImage?]
    var iconSide: CGFloat
    var labelWidth: CGFloat
    var armed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                folderIcon
                    .frame(width: iconSide, height: iconSide)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: labelWidth)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(GridPlainButtonStyle())
        .fixedSize()
        .help(name)
        .accessibilityLabel(name)
    }

    private var folderIcon: some View {
        let mini = iconSide / 3.6
        return RoundedRectangle(cornerRadius: iconSide * 0.22, style: .continuous)
            .fill(Color.white.opacity(armed ? 0.28 : 0.16))
            .overlay {
                RoundedRectangle(cornerRadius: iconSide * 0.22, style: .continuous)
                    .strokeBorder(Color.white.opacity(armed ? 0.95 : 0.28), lineWidth: armed ? 3 : 1)
            }
            .overlay {
                LazyVGrid(columns: Array(repeating: SwiftUI.GridItem(.fixed(mini), spacing: 3), count: 3), spacing: 3) {
                    ForEach(0..<9, id: \.self) { index in
                        miniIcon(index < icons.count ? icons[index] : nil, side: mini)
                    }
                }
                .padding(iconSide * 0.12)
            }
    }

    private func miniIcon(_ image: NSImage?, side: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
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
