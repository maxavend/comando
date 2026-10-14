import AppKit
import SwiftTerm
import SwiftUI

/// The animated “…” bubble from Messages, shown until the first output arrives.
struct TypingIndicator: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous))
            .frame(width: 52, height: 34)
            .background(.fill.secondary, in: .rect(cornerRadius: 17))
            .accessibilityLabel("Ejecutando")
    }
}
