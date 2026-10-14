import SwiftUI

/// Shown while something is dragged over the chat.
struct DropHint: View {
    var body: some View {
        Label("Suelta una carpeta para ir a ella, o un archivo para escribir su ruta", systemImage: "arrow.down.doc")
            .font(.callout)
            .padding(.horizontal, Metrics.bubbleHorizontalPadding + 4)
            .padding(.vertical, Metrics.bubbleVerticalPadding + 2)
            .glassEffect(.regular, in: .capsule)
    }
}
