import SwiftUI
import UniformTypeIdentifiers

struct PageControls: View {
    @ObservedObject var model: GridBackModel

    var body: some View {
        HStack(spacing: 16) {
            pageArrow(systemName: "chevron.left", enabled: model.currentPage > 0, label: String(localized: "Previous page")) {
                model.selectPage(model.currentPage - 1)
            } onDropID: { id in
                model.moveToPreviousPage(id)
            }

            HStack(spacing: 8) {
                ForEach(model.layout.pages.indices, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index == model.currentPage ? 0.95 : 0.35))
                        .frame(width: index == model.currentPage ? 8 : 6, height: index == model.currentPage ? 8 : 6)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectPage(index) }
                        .accessibilityLabel(String(localized: "Page \(index + 1)"))
                        .accessibilityAddTraits(index == model.currentPage ? .isSelected : [])
                }
            }

            pageArrow(systemName: "chevron.right", enabled: model.currentPage + 1 < model.layout.pages.count, label: String(localized: "Next page")) {
                model.selectPage(model.currentPage + 1)
            } onDropID: { id in
                model.moveToNextPage(id)
            }

            if !model.layout.pages.isEmpty {
                Text(String(localized: "Page \(model.currentPage + 1) of \(model.layout.pages.count)"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(minWidth: 88, alignment: .leading)
            }
        }
    }

    private func pageArrow(
        systemName: String,
        enabled: Bool,
        label: String,
        action: @escaping () -> Void,
        onDropID: @escaping (String) -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.28))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .accessibilityLabel(label)
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                DroppedAppID.load(from: providers) { id in
                    guard let id else { return }
                    onDropID(id)
                }
                return true
            }
    }
}
