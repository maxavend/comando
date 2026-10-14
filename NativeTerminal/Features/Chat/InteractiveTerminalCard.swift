import SwiftUI

/// A full terminal for programs that take over the screen (vim, top, less) or
/// need raw keyboard input (ssh, REPLs).
struct InteractiveTerminalCard: View {
    let live: LiveOutput
    let shell: ShellSession

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Label(live.command, systemImage: "rectangle.inset.filled.and.cursorarrow")
                    .font(.system(size: fontSize))
                    .lineLimit(1)
                Spacer()
                Text("El teclado va directo al programa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
