import SwiftUI

struct OutputBubble<Accessory: View>: View {
    let output: AttributedString
    let plainText: String
    @ViewBuilder let accessory: Accessory

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isHovering = false

    var body: some View {
        let firstLineCenter = Metrics.singleLineBubbleHeight(fontSize: fontSize) / 2
        let gap = Metrics.replySpacing
        VStack(alignment: .leading, spacing: Metrics.bubbleVerticalPadding) {
            accessory
            Text(output)
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bubble(.reply)
        .overlay(alignment: .topTrailing) {
            // Sits just outside the bubble, centered on its first line.
            CopyButton(text: plainText)
                .alignmentGuide(.trailing) { $0[.leading] - gap }
                .alignmentGuide(.top) { $0[VerticalAlignment.center] - firstLineCenter }
                .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
        .padding(.trailing, Metrics.bubbleOppositeInset)
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
