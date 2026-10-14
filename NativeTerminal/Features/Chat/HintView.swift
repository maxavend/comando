import SwiftUI

/// A plain-language explanation of a failure, with a command to try.
struct HintView: View {
    let message: String
    let suggestion: String?
    let onUseSuggestion: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion {
                    Button("Usar “\(suggestion)”") { onUseSuggestion(suggestion) }
                        .buttonStyle(.link)
                        .pointerStyle(.link)
                        .foregroundStyle(.tint)
                        .help("Escribe este comando en el campo para revisarlo antes de enviarlo")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.bubbleHorizontalPadding)
        .padding(.trailing, Metrics.bubbleOppositeInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
