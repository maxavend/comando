import AppKit
import SwiftUI

struct CommandBubble: View {
    let command: String
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        Text(command)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.tint, in: .rect(cornerRadius: 17))
            .accessibilityLabel("Comando: \(command)")
    }
}
