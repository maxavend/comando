import SwiftUI

/// The animated “…” bubble from Messages, shown until the first output arrives.
struct TypingIndicator: View {
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        // A hidden line of text gives the bubble exactly the height of a one-line reply.
        Text(verbatim: "0000")
            .font(.system(size: fontSize))
            .hidden()
            .overlay {
                Image(systemName: "ellipsis")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous))
            }
            .bubble(.reply)
            .accessibilityElement()
            .accessibilityLabel("Ejecutando")
    }
}
