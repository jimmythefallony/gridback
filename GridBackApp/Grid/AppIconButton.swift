import AppKit
import GridBackCore
import SwiftUI

struct AppIconButton: View {
    let title: String
    let image: NSImage?
    var isSelected = false
    var iconSide: CGFloat = 96
    var labelWidth: CGFloat = 128
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.ink) private var ink

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon
                    .frame(width: iconSide, height: iconSide)
                    .scaleEffect(isHovering ? 1.06 : 1)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ink.label.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: labelWidth)
                    .gridTextShadow(ink.labelShadow)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ink.iconHighlight(selected: isSelected, hovering: isHovering).color)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(GridPlainButtonStyle())
        .fixedSize()
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder
    private var icon: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: iconSide * 0.55))
                .foregroundStyle(ink.quiet.color)
        }
    }
}

/// Draws no extra highlight of its own. The icon button paints only the
/// shape around the icon and the label.
struct GridPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
