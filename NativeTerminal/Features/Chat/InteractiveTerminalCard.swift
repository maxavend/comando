import AppKit
import SwiftTerm
import SwiftUI

/// A full terminal for programs that take over the screen (vim, top, less) or
/// need raw keyboard input (ssh, REPLs).
struct InteractiveTerminalCard: View {
    let live: LiveOutput
    let shell: ShellSession

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(live.command, systemImage: "rectangle.inset.filled.and.cursorarrow")
                    .font(.callout.monospaced())
                    .lineLimit(1)
                Spacer()
                Text("El teclado va directo al programa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            EmbeddedTerminal(shell: shell, fontSize: fontSize)
                .frame(height: 440)
        }
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator)
        }
    }
}
