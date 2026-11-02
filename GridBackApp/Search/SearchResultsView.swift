import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var model: GridBackModel

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 12),
            count: max(model.layout.metrics.columns, 1)
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(model.searchQuery)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.12), in: Capsule())
            .frame(maxWidth: 520)
            .accessibilityLabel(String(localized: "Search"))

            if model.searchResults.isEmpty {
                Text(String(localized: "No matching apps"))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(model.searchResults.enumerated()), id: \.element.id) { index, record in
                            AppIconButton(
                                title: record.displayName,
                                image: model.iconImages[record.id],
                                isSelected: index == model.selectedResultIndex,
                                iconSide: 64
                            ) {
                                model.launch(id: record.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 24)
                }
            }

            Text(String(localized: "Return opens the highlighted app  ·  Esc clears search"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}
