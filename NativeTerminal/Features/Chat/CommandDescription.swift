import SwiftUI

/// What a command does, in plain words, beside its bubble on hover. Clicking
/// it explains the command piece by piece.
struct CommandDescription: View {
    let text: String
    let command: String
    /// Shown while the pointer is over the command (or over this).
    var isVisible = true

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
        .fixedSize()
        .onHover { isHovering = $0 }
        .opacity(isVisible || isHovering || isExplaining ? 1 : 0)
        .animation(.easeOut(duration: 0.15), value: isVisible || isHovering)
        .help("¿Qué hace este comando?")
        .accessibilityIdentifier("commandDescription")
        .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
            CommandBreakdownView(command: command)
        }
    }
}
