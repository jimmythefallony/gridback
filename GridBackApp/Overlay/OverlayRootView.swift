import GridBackCore
import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var model: GridBackModel
    @State private var reorder: GridReorderSession?
    @State private var finger: CGPoint = .zero
    @State private var gridFrame: CGRect = .zero
    @State private var blockLaunch = false

    var body: some View {
        GeometryReader { overlay in
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if reorder == nil {
                            model.hideOverlay()
                        }
                    }

                Group {
                    if model.isSearching {
                        SearchResultsView(model: model)
                    } else {
                        AppGridView(
                            model: model,
                            page: reorder?.page ?? model.currentPage,
                            pages: reorder?.preview.pages ?? model.layout.pages,
                            hiddenID: reorder?.appID,
                            blockLaunch: blockLaunch
                        )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 24)

                if let reorder {
                    AppIconButton(
                        title: model.appsByID[reorder.appID]?.displayName ?? reorder.appID,
                        image: model.iconImages[reorder.appID],
                        iconSide: 84
                    ) {}
                    .frame(width: 120, height: 140)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                    .position(finger)
                    .allowsHitTesting(false)
                }

                if let warning = model.persistenceWarning {
                    banner(warning, color: Color.orange.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 18)
                }

                if let launchError = model.launchError {
                    banner(launchError, color: Color.red.opacity(0.92))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 36)
                }
            }
            .coordinateSpace(name: "overlay")
            .onPreferenceChange(GridFramePreferenceKey.self) { gridFrame = $0 }
            .simultaneousGesture(reorderGesture(overlayWidth: overlay.size.width))
        }
    }

    private func reorderGesture(overlayWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .named("overlay"))
            .onChanged { value in
                guard !model.isSearching else { return }
                if reorder == nil {
                    guard let id = iconID(at: value.startLocation) else { return }
                    reorder = GridReorderSession(
                        appID: id,
                        layout: model.layout,
                        page: model.currentPage
                    )
                    blockLaunch = true
                }
                finger = value.location
                updateReorder(at: value.location, overlayWidth: overlayWidth)
            }
            .onEnded { _ in
                if let reorder {
                    model.commitReorder(reorder.preview, page: reorder.page)
                }
                reorder = nil
                DispatchQueue.main.async {
                    blockLaunch = false
                }
            }
    }

    private func updateReorder(at point: CGPoint, overlayWidth: CGFloat) {
        guard var session = reorder else { return }
        let edge = GridDragResolver.pageEdge(x: Double(point.x), overlayWidth: Double(overlayWidth))
        let slot = slot(at: point)
        session.hover(slot: edge == nil ? slot : nil, edge: edge)
        reorder = session
    }

    private func iconID(at point: CGPoint) -> String? {
        guard let slot = slot(at: point) else { return nil }
        let pages = model.layout.pages
        let page = min(model.currentPage, max(pages.count - 1, 0))
        guard pages.indices.contains(page), slot < pages[page].count else { return nil }
        return pages[page][slot]
    }

    private func slot(at point: CGPoint) -> Int? {
        let metrics = model.layout.metrics.clamped
        guard gridFrame.width > 0, gridFrame.height > 0 else { return nil }
        return GridDragResolver.slot(
            x: Double(point.x - gridFrame.minX),
            y: Double(point.y - gridFrame.minY),
            cellWidth: Double(gridFrame.width) / Double(metrics.columns),
            cellHeight: Double(gridFrame.height) / Double(metrics.rows),
            columns: metrics.columns,
            rows: metrics.rows
        )
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color, in: Capsule())
            .shadow(radius: 8, y: 2)
    }
}
