import SwiftUI

/// The first Liquid Glass slice. Set this to false to keep the previous materials.
enum LiquidGlass {
    static let isEnabled = true
}

extension View {
    /// Folder panel plate. Reduce Transparency, or a disabled flag, keeps the old material.
    func folderPanelPlate(cornerRadius: CGFloat) -> some View {
        modifier(FolderPanelPlate(cornerRadius: cornerRadius))
    }

    /// Search field plate. Same switch as the folder panel.
    func searchFieldPlate() -> some View {
        modifier(SearchFieldPlate())
    }
}

private struct FolderPanelPlate: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if LiquidGlass.isEnabled, !reduceTransparency {
            content
                .clipShape(shape)
                .background {
                    Color.clear.glassEffect(.regular, in: shape)
                }
        } else {
            content
                .background {
                    shape
                        .fill(Color.white.opacity(0.24))
                        .background(.ultraThinMaterial, in: shape)
                }
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                }
                .clipShape(shape)
        }
    }
}

private struct SearchFieldPlate: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = Capsule()
        if LiquidGlass.isEnabled, !reduceTransparency {
            content
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .background {
                    Color.clear.glassEffect(.regular, in: shape)
                }
        } else {
            content.background(Color.white.opacity(0.16), in: shape)
        }
    }
}
