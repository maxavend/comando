import SwiftUI

struct InteractiveSummary: View {
    let entry: CommandEntry
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.bubbleVerticalPadding) {
            Label("Sesión interactiva", systemImage: "rectangle.inset.filled.and.cursorarrow")
                .foregroundStyle(.secondary)
            if let transcript = entry.transcript {
                DisclosureGroup("Transcripción", isExpanded: $isExpanded) {
                    Text(transcript)
                        .font(.system(size: fontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .fixedSize(horizontal: !isExpanded, vertical: false)
        .bubble(.reply)
        .padding(.trailing, Metrics.bubbleOppositeInset)
    }
}
