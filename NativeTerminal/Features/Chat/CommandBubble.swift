import SwiftUI

struct CommandBubble: View {
    let command: String
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        Text(command)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .bubble(.command)
            .accessibilityLabel("Comando: \(command)")
    }
}
