import AppKit
import SwiftUI

struct OutputBubble<Accessory: View>: View {
    let output: AttributedString
    let plainText: String
    @ViewBuilder let accessory: Accessory

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            accessory
            Text(output)
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BubbleMetrics.horizontalPadding)
        .padding(.vertical, 8)
        .background(.fill.secondary, in: .rect(cornerRadius: 17))
        .overlay(alignment: .topTrailing) {
            Button("Copiar salida", systemImage: "doc.on.doc") {
                Pasteboard.copy(plainText)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("Copiar salida")
            .padding(6)
            .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
        .padding(.trailing, BubbleMetrics.trailingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Salida")
    }
}

extension OutputBubble where Accessory == EmptyView {
    init(output: AttributedString, plainText: String) {
        self.init(output: output, plainText: plainText) { EmptyView() }
    }
}
