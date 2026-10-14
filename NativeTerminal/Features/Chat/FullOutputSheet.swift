import SwiftUI

/// The whole output of a command, laid out like a standard macOS sheet:
/// header, content and the actions at the bottom trailing edge.
struct FullOutputSheet: View {
    let command: String
    let output: Data
    let lineCount: Int

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("^[\(lineCount) línea](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.contentInset)

            Divider()

            OutputTextView(output: output, fontSize: fontSize)

            Divider()

            HStack {
                Spacer()
                Button("Copiar todo", action: copyAll)
                Button("Listo", action: close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Metrics.contentInset)
        }
        .frame(minWidth: 640, idealWidth: 820, minHeight: 420, idealHeight: 620)
        #if DEBUG
        .onDebugAction("#close") { _ in dismiss() }
        #endif
    }

    private func copyAll() {
        Pasteboard.copy(OutputRenderer.plainText(raw: [UInt8](output)))
    }

    private func close() {
        dismiss()
    }
}
