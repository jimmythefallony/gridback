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
            TextField(String(localized: "Search"), text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .foregroundStyle(.white)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18)
        .frame(width: 280, height: 40)
        .background(Color.white.opacity(0.16), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .accessibilityLabel(String(localized: "Search"))
        .accessibilityValue(query)
    }
}
