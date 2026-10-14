import AppKit
import SwiftUI

struct InteractiveSummary: View {
    let entry: CommandEntry
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sesión interactiva", systemImage: "rectangle.inset.filled.and.cursorarrow")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let transcript = entry.transcript {
                DisclosureGroup("Transcripción", isExpanded: $isExpanded) {
                    Text(transcript)
                        .font(.system(size: fontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.secondary, in: .rect(cornerRadius: 17))
        .padding(.trailing, BubbleMetrics.trailingInset)
    }
}
