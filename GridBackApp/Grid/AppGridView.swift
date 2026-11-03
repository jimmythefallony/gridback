import SwiftUI

struct AppGridView: View {
    @ObservedObject var model: GridBackModel
    var page: Int
    var pages: [[String]]
    var hiddenID: String?
    var blockLaunch: Bool

    var body: some View {
        VStack(spacing: 18) {
            if model.isScanning && model.appsByID.isEmpty {
                status(String(localized: "Looking for apps…"))
            } else if pages.isEmpty {
                status(String(localized: "No apps found in Applications, System Applications, or your home Applications folder."))
            } else {
                GeometryReader { geo in
                    pageGrid(in: geo.size)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: GridFramePreferenceKey.self,
                                    value: proxy.frame(in: .named("overlay"))
                                )
                            }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                PageControls(model: model, page: page, pageCount: pages.count)
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
        let pageIndex = min(page, max(pages.count - 1, 0))
        let ids = pages.indices.contains(pageIndex) ? pages[pageIndex] : []
        let cellWidth = size.width / CGFloat(metrics.columns)
        let cellHeight = size.height / CGFloat(metrics.rows)
        let iconSide = min(max(min(cellWidth, cellHeight) * 0.52, 48), 112)

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<metrics.rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<metrics.columns, id: \.self) { column in
                            let slot = row * metrics.columns + column
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if slot >= ids.count {
                                        model.hideOverlay()
                                    }
                                }
                                .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
            ForEach(Array(ids.enumerated()), id: \.element) { slot, id in
                if id != hiddenID {
                    AppIconButton(
                        title: model.appsByID[id]?.displayName ?? id,
                        image: model.iconImages[id],
                        iconSide: iconSide
                    ) {
                        guard !blockLaunch else { return }
                        model.launch(id: id)
                    }
                    .frame(width: cellWidth, height: cellHeight)
                    .position(
                        x: (CGFloat(slot % metrics.columns) + 0.5) * cellWidth,
                        y: (CGFloat(slot / metrics.columns) + 0.5) * cellHeight
                    )
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.16), value: ids)
    }
}

struct GridFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}
