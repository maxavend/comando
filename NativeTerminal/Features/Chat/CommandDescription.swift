import SwiftUI

/// What a command does, in plain words, under its bubble. Clicking it explains
/// the command piece by piece.
struct CommandDescription: View {
    let text: String
    let command: String

    @State private var isExplaining = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isExplaining = true
        } label: {
            HStack(spacing: 3) {
                Text(text)
                Image(systemName: "info.circle")
                    .opacity(isHovering ? 1 : 0.6)
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .frame(height: Metrics.statusLineHeight)
        .padding(.trailing, Metrics.bubbleHorizontalPadding)
        .onHover { isHovering = $0 }
        .help("¿Qué hace este comando?")
        .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
            CommandBreakdownView(command: command)
        }
    }
}
