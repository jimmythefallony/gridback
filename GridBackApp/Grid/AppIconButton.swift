import AppKit
import SwiftUI

struct AppIconButton: View {
    let title: String
    let image: NSImage?
    var isSelected = false
    var iconSide: CGFloat = 72
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon
                    .frame(width: iconSide, height: iconSide)
                    .scaleEffect(isHovering ? 1.08 : 1)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 32)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
                .padding(4)
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
