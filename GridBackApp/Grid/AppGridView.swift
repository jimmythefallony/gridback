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
                    .position(x: layout.columnCenter(slot), y: layout.rowCenter(slot))
                }
            }
        }
        .frame(width: layout.gridWidth, height: layout.gridHeight)
        .animation(.easeInOut(duration: 0.16), value: ids)
    }
}

struct SearchPill: View {
    var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text(query.isEmpty ? String(localized: "Search") : query)
                .lineLimit(1)
                .foregroundStyle(.white.opacity(query.isEmpty ? 0.62 : 1))
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18)
        .frame(width: 280, height: 40)
        .background(Color.white.opacity(0.16), in: Capsule())
        .accessibilityLabel(String(localized: "Search"))
        .accessibilityValue(query)
    }
}
