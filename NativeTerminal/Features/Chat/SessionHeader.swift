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
    static let overhang: CGFloat = 24

    // As in the contact header in Messages (measured at 1:1): a 40-point
    // avatar, and a 28-point capsule with the name in the body text style,
    // overlapping the avatar's lower edge a little.
    private static let avatarSize: CGFloat = 40
    /// How far the avatar reaches over the name capsule.
    private static let gap: CGFloat = -5

    @Environment(TerminalController.self) private var controller
    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            // Like Messages: the avatar in front, over the name capsule's edge.
            VStack(spacing: Self.gap) {
                SessionAvatar(isRunning: isRunning, emoji: session.emoji, colorIndex: session.colorIndex,
                              size: Self.avatarSize, symbol: session.avatarSymbol(for: directory))
                    // In front: the avatar sits over the capsule's top edge.
                    .zIndex(1)
                HStack(spacing: 2) {
                    Text(session.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("En \(ShellEscape.abbreviate(directory)). Clic para cambiar su nombre, emoji y color.")
        .accessibilityLabel("Sesión \(session.displayName), en \(FolderName.display(directory))")
        .accessibilityHint("Cambia su nombre, emoji y color")
        #if DEBUG
        .onDebugAction("#editappearance") { _ in isEditing = true }
        #endif
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            SessionAppearanceEditor(session: session) { controller.save() }
        }
    }
}
