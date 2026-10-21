import SwiftUI

struct CommandBubble: View {
    let command: String
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        // Not selectable, like a bubble in Messages: selectable text answers a
        // right-click with the system's text menu instead of the command's own
        // (which has Copiar comando).
        Text(command)
            .font(.system(size: fontSize))
            .foregroundStyle(.white)
            .bubble(.command)
            .accessibilityLabel("Comando: \(command)")
    }
}
