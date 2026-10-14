import SwiftUI

/// A starter action in an empty session. It shows the real command it runs,
/// so people learn the command while using the button.
struct SuggestionCard: View {
    let title: LocalizedStringKey
    let systemImage: String
    let command: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
                Label(title, systemImage: systemImage)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Text(command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.vertical, Metrics.bubbleHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovering ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary),
                in: .rect(cornerRadius: Metrics.bubbleCornerRadius)
            )
            .contentShape(.rect(cornerRadius: Metrics.bubbleCornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
