import SwiftUI

struct PageControls: View {
    @ObservedObject var model: GridBackModel
    var page: Int
    var pageCount: Int

    var body: some View {
        HStack(spacing: 16) {
            pageArrow(systemName: "chevron.left", enabled: page > 0, label: String(localized: "Previous page")) {
                model.selectPage(page - 1)
            }

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index == page ? 0.95 : 0.35))
                        .frame(width: index == page ? 8 : 6, height: index == page ? 8 : 6)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectPage(index) }
                        .accessibilityLabel(String(localized: "Page \(index + 1)"))
                        .accessibilityAddTraits(index == page ? .isSelected : [])
                }
            }

            pageArrow(
                systemName: "chevron.right",
                enabled: page + 1 < pageCount,
                label: String(localized: "Next page")
            ) {
                model.selectPage(page + 1)
            }

            if pageCount > 0 {
                Text(String(localized: "Page \(page + 1) of \(pageCount)"))
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
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.28))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .accessibilityLabel(label)
    }
}
