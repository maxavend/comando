import SwiftUI

struct CommandBubble: View {
    let command: String
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        // Like a bubble in Messages, a right-click anywhere on it opens the
        // command's own menu (Copiar comando…), not the system's text menu.
        DrawnText(command)
            .font(.system(size: fontSize))
            .foregroundStyle(.white)
            .bubble(.command)
            .contentShape(.rect)
            .accessibilityLabel("Comando: \(command)")
    }
}
