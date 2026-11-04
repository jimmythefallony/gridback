import SwiftUI

struct PageControls: View {
    var pageCount: Int
    var position: CGFloat
    var onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 18) {
            pageArrow(systemName: "chevron.left", enabled: pageCount > 0 && position > 0.5, label: String(localized: "Previous page")) {
                onSelect(max(Int(position.rounded()) - 1, 0))
            }

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    let distance = min(abs(position - CGFloat(index)), 1)
                    Circle()
                        .fill(Color.white.opacity(0.95 - Double(distance) * 0.62))
                        .frame(width: 8 - distance * 2.5, height: 8 - distance * 2.5)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(index) }
                        .accessibilityLabel(String(localized: "Page \(index + 1)"))
                        .accessibilityAddTraits(distance < 0.5 ? .isSelected : [])
                }
            }

            pageArrow(
                systemName: "chevron.right",
                enabled: pageCount > 0 && position < CGFloat(pageCount - 1) - 0.5,
                label: String(localized: "Next page")
            ) {
                onSelect(min(Int(position.rounded()) + 1, max(pageCount - 1, 0)))
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
