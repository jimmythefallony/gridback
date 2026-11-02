import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var model: GridBackModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.hideOverlay() }

            Group {
                if model.isSearching {
                    SearchResultsView(model: model)
                } else {
                    AppGridView(model: model)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 24)

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
