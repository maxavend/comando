import SwiftUI

/// A full terminal for programs that take over the screen (vim, top, less) or
/// need raw keyboard input (ssh, REPLs).
struct InteractiveTerminalCard: View {
    let live: LiveOutput
    let shell: ShellSession

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @Environment(TerminalController.self) private var controller

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Label(live.command, systemImage: "rectangle.inset.filled.and.cursorarrow")
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                Spacer()
                if let chat = controller.agentChats[shell.id] {
                    // The conversation's screen, opened from the chat: one
                    // click goes back to bubbles.
                    Button("Volver al chat", systemImage: "bubble.left.and.bubble.right") {
                        if let session = controller.session(withID: shell.id) { controller.returnToAgentChat(in: session) }
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .help("Cierra la pantalla de \(chat.kind.rawValue) y sigue la conversación en el chat")
                } else {
                    Text(AICommandLine.isAgent(live.command)
                         ? "Escríbele aquí o en el campo de abajo"
                         : "El teclado va directo al programa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.vertical, Metrics.bubbleVerticalPadding)

            Divider()

            EmbeddedTerminal(shell: shell, fontSize: fontSize)
                .padding(.leading, Metrics.bubbleHorizontalPadding)
                .padding(.vertical, Metrics.bubbleVerticalPadding)
                .frame(height: Metrics.embeddedTerminalHeight)
        }
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: Metrics.cardCornerRadius))
        .clipShape(.rect(cornerRadius: Metrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .strokeBorder(.separator)
        }
    }
}
