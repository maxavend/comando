import SwiftUI

/// The session's identity over the top of the chat, like the contact at the
/// top of a conversation in Messages: a large avatar, and its name in a glass
/// capsule over the avatar's lower edge. Opens the session's name, emoji and color.
struct SessionHeader: View {
    let session: TerminalSession
    let directory: String
    let isRunning: Bool

    /// Distance from the top of the window to the avatar.
    static let topInset: CGFloat = 6
    /// How far the name hangs below the title bar, into the chat.
    static let overhang: CGFloat = 16

    private static let avatarSize: CGFloat = 40

    @Environment(TerminalController.self) private var controller
    @State private var isEditing = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            VStack(spacing: -9) {
                SessionAvatar(isRunning: isRunning, emoji: session.emoji, colorIndex: session.colorIndex,
                              size: Self.avatarSize, symbol: SessionSymbol.symbol(for: directory))
                HStack(spacing: 3) {
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .scaleEffect(isHovering ? 1.03 : 1)
            .animation(.smooth(duration: 0.15), value: isHovering)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("En \(ShellEscape.abbreviate(directory)). Clic para cambiar su nombre, emoji y color.")
        .accessibilityLabel("Sesión \(session.displayName), en \(FolderName.display(directory))")
        .accessibilityHint("Cambia su nombre, emoji y color")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            SessionAppearanceEditor(session: session) { controller.save() }
        }
    }
}
