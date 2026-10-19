import SwiftUI

/// The session's identity over the top of the chat, like the contact at the
/// top of a conversation in Messages: its avatar, and its name in a small glass
/// capsule that just touches it. Opens the session's name, emoji and color.
struct SessionHeader: View {
    let session: TerminalSession
    let directory: String
    let isRunning: Bool

    /// Distance from the top of the window to the avatar.
    static let topInset: CGFloat = 6
    /// How far the name hangs below the title bar, into the chat.
    static let overhang: CGFloat = 14

    // Measured from the contact header in Messages: a 32-point avatar whose
    // lower edge just touches a 23-point capsule with the name in 10.5 points.
    private static let avatarSize: CGFloat = 32
    /// The avatar and the name capsule just touch.
    private static let gap: CGFloat = -2

    @Environment(TerminalController.self) private var controller
    @State private var isEditing = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            // Like Messages: the avatar in front, and the name in a capsule
            // that just touches it; the capsule's padding keeps the text clear.
            VStack(spacing: Self.gap) {
                SessionAvatar(isRunning: isRunning, emoji: session.emoji, colorIndex: session.colorIndex,
                              size: Self.avatarSize, symbol: SessionSymbol.symbol(for: directory))
                    .zIndex(1)
                HStack(spacing: 2) {
                    Text(session.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
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
