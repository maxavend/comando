import SwiftUI

/// “¿Qué hace esto?”: each piece of a command and what it means.
struct CommandBreakdownView: View {
    let command: String

    var body: some View {
        let parts = CommandExplainer.parts(of: command)
        VStack(alignment: .leading, spacing: Metrics.composerSpacing) {
            Text("¿Qué hace este comando?")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.bubbleHorizontalPadding, verticalSpacing: Metrics.composerSpacing) {
                ForEach(parts) { part in
                    GridRow {
                        Text(part.token)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.quaternary, in: .rect(cornerRadius: 5))
                            .frame(maxWidth: 140, alignment: .leading)
                        Text(part.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(Metrics.contentInset)
        .frame(width: 380, alignment: .leading)
    }
}
