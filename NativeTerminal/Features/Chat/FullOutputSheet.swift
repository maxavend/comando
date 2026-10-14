import AppKit
import SwiftTerm
import SwiftUI

/// Shows very long output in a native text view, which handles large text far
/// better than a SwiftUI `Text`.
struct FullOutputSheet: View {
    let command: String
    let output: Data

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        NavigationStack {
            OutputTextView(output: output, fontSize: fontSize)
                .navigationTitle(command)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Copiar todo", systemImage: "doc.on.doc") {
                            Pasteboard.copy(OutputRenderer.plainText(raw: [UInt8](output)))
                        }
                    }
                }
        }
        .frame(minWidth: 640, idealWidth: 860, minHeight: 420, idealHeight: 640)
    }
}
