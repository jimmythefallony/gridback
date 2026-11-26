import GridBackCore
import SwiftUI

struct PageControls: View {
    var pageCount: Int
    var position: CGFloat
    /// The page the model has committed. Selection updates with this, while
    /// `position` still follows the moving strip.
    var selectedPage: Int
    var onSelect: (Int) -> Void
    @Environment(\.ink) private var ink

    var body: some View {
        HStack(spacing: 18) {
            pageArrow(systemName: "chevron.left", enabled: pageCount > 0 && selectedPage > 0, label: String(localized: "Previous page")) {
                onSelect(max(selectedPage - 1, 0))
            }

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    let distance = min(abs(position - CGFloat(index)), 1)
                    Circle()
                        .fill(ink.pageDot(distance: Double(distance)).color)
                        .frame(width: 8 - distance * 2.5, height: 8 - distance * 2.5)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(index) }
                        .accessibilityLabel(String(localized: "Page \(index + 1)"))
                        .accessibilityAddTraits(index == selectedPage ? .isSelected : [])
                }
            }

            pageArrow(
                systemName: "chevron.right",
                enabled: pageCount > 0 && selectedPage < pageCount - 1,
                label: String(localized: "Next page")
            ) {
                onSelect(min(selectedPage + 1, max(pageCount - 1, 0)))
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
            .foregroundStyle(ink.pageArrow(enabled: enabled).color)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .accessibilityLabel(label)
    }
}
