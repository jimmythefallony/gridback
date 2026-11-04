import GridBackCore
import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var model: GridBackModel
    var layout: LaunchGridLayout

    var body: some View {
        Group {
            if model.searchResults.isEmpty {
                Text(String(localized: "No matching apps"))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(layout.columnStride), spacing: 0),
                            count: layout.columns
                        ),
                        spacing: 0
                    ) {
                        ForEach(Array(model.searchResults.enumerated()), id: \.element.id) { index, record in
                            AppIconButton(
                                title: record.displayName,
                                image: model.iconImages[record.id],
                                isSelected: index == model.selectedResultIndex,
                                iconSide: layout.iconSide,
                                labelWidth: layout.hitWidth - 12
                            ) {
                                model.launch(id: record.id)
                            }
                            .frame(width: layout.columnStride, height: layout.rowStride)
                        }
                    }
                    .frame(width: layout.gridWidth)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
