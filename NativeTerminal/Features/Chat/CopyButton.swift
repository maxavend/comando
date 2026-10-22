import SwiftUI

struct CopyButton: View {
    let text: String
    var label: LocalizedStringKey = "Copiar salida"

    var body: some View {
        Button(label, systemImage: "doc.on.doc", action: copy)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help(label)
    }

    private func copy() {
        Pasteboard.copy(text)
    }
}
