import SwiftUI

struct CopyButton: View {
    let text: String

    var body: some View {
        Button("Copiar salida", systemImage: "doc.on.doc", action: copy)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("Copiar salida")
    }

    private func copy() {
        Pasteboard.copy(text)
    }
}
