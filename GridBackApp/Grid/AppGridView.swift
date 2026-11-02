import SwiftUI
import UniformTypeIdentifiers

struct AppGridView: View {
    @ObservedObject var model: GridBackModel

    var body: some View {
        VStack(spacing: 18) {
            if model.isScanning && model.appsByID.isEmpty {
                status(String(localized: "Looking for apps…"))
            } else if model.layout.pages.isEmpty {
                status(String(localized: "No apps found in Applications, System Applications, or your home Applications folder."))
            } else {
                GeometryReader { geo in
                    pageGrid(in: geo.size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                PageControls(model: model)
                Text(String(localized: "Type to search  ·  Drag to rearrange  ·  Esc closes"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageGrid(in size: CGSize) -> some View {
        let metrics = model.layout.metrics.clamped
        let pageIndex = min(model.currentPage, max(model.layout.pages.count - 1, 0))
        let ids = model.layout.pages.indices.contains(pageIndex) ? model.layout.pages[pageIndex] : []
        let cellWidth = size.width / CGFloat(metrics.columns)
        let cellHeight = size.height / CGFloat(metrics.rows)
        let iconSide = min(max(min(cellWidth, cellHeight) * 0.52, 48), 112)

        return VStack(spacing: 0) {
            ForEach(0..<metrics.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<metrics.columns, id: \.self) { column in
                        let slot = row * metrics.columns + column
                        cell(ids: ids, slot: slot, page: pageIndex, iconSide: iconSide)
                            .frame(width: cellWidth, height: cellHeight)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func cell(ids: [String], slot: Int, page: Int, iconSide: CGFloat) -> some View {
        if slot < ids.count {
            let id = ids[slot]
            AppIconButton(
                title: model.appsByID[id]?.displayName ?? id,
                image: model.iconImages[id],
                iconSide: iconSide
            ) {
                model.launch(id: id)
            }
            .onDrag { DroppedAppID.provider(for: id) }
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                DroppedAppID.load(from: providers) { dragged in
                    guard let dragged else { return }
                    model.move(appID: dragged, toPage: page, toSlot: slot)
                }
                return true
            }
        } else {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.hideOverlay() }
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    DroppedAppID.load(from: providers) { dragged in
                        guard let dragged else { return }
                        model.move(appID: dragged, toPage: page, toSlot: slot)
                    }
                    return true
                }
        }
    }
}
