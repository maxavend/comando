import SwiftUI

/// The session's identity at the top of the chat, like the contact at the top
/// of a conversation in Messages: its avatar, and its name in a small glass
/// capsule that opens the session's name, emoji and color.
struct SessionHeader: View {
    let session: TerminalSession
    let directory: String
    let isRunning: Bool

    @Environment(TerminalController.self) private var controller
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            VStack(spacing: -3) {
                SessionAvatar(isRunning: isRunning, emoji: session.emoji, colorIndex: session.colorIndex, size: 26)
                    .zIndex(1)
                HStack(spacing: 2) {
                    Text(session.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Metrics.composerSpacing)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: .capsule)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(ShellEscape.abbreviate(directory))
        .accessibilityLabel("Sesión \(session.displayName), en \(FolderName.display(directory))")
        .accessibilityHint("Cambia su nombre, emoji y color")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            SessionAppearanceEditor(session: session) { controller.save() }
        }
    }
}
