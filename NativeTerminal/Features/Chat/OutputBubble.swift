import SwiftUI

struct OutputBubble: View {
    let output: AttributedString
    let plainText: String
    /// Columns (ls, tables) keep a monospaced font; prose uses the system font.
    var monospaced = false
    /// Lines in `output`, for output that folds when it's long; nil never folds.
    var lineCount: Int?
    /// Opens the whole output, for output longer than the bubble keeps.
    var onShowAll: (() -> Void)?

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var textHeight: CGFloat = 0

    /// Long output folds to the height of its last rows, which is usually
    /// where the result or the error is, and which follow along while it runs.
    /// Counted in rows, not lines, so a few long lines that wrap fold too.
    static let foldThreshold = 24
    static let foldedRows = 10

    var body: some View {
        let lineHeight = Metrics.singleLineBubbleHeight(fontSize: fontSize, monospaced: monospaced) - Metrics.bubbleVerticalPadding * 2
        let foldedHeight = lineHeight * CGFloat(Self.foldedRows)
        // Past the threshold only the last lines are laid out, which is cheap
        // and still taller than the fold.
        let hasManyLines = (lineCount ?? 0) > Self.foldThreshold
        let isFoldable = lineCount != nil && (hasManyLines || textHeight > lineHeight * CGFloat(Self.foldThreshold) * 0.7)
        let isFolded = isFoldable && !isExpanded
        let firstLineCenter = Metrics.singleLineBubbleHeight(fontSize: fontSize, monospaced: monospaced) / 2
        let gap = Metrics.replySpacing
        TextWithFooter(spacing: Metrics.bubbleVerticalPadding) {
            LinkAwareText(content: isFolded && hasManyLines ? output.lastLines(Self.foldedRows) : output)
                .font(.system(size: fontSize, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                .frame(height: isFolded ? min(textHeight, foldedHeight) : nil, alignment: .bottom)
                .clipped()
                // The rows above the fold fade out instead of being cut.
                .mask {
                    LinearGradient(stops: [.init(color: isFolded && textHeight > foldedHeight + 1 ? .clear : .black, location: 0),
                                           .init(color: .black, location: isFolded ? 0.25 : 0)],
                                   startPoint: .top, endPoint: .bottom)
                }
            if isFoldable {
                // One link: unfold here; when even that is cut short, the
                // whole output opens in a window.
                HStack(spacing: Metrics.bubbleHorizontalPadding) {
                    if !isFolded, let onShowAll {
                        Button("Ver todo", action: onShowAll)
                    }
                    Button(isFolded ? "Ver más" : "Ver menos") {
                        withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() }
                    }
                }
                .buttonStyle(.link)
                .pointerStyle(.link)
                .foregroundStyle(.tint)
            }
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
        .modifier(OutputWidth(isColumns: monospaced))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Salida")
    }
}

/// The text on the leading edge and the links under it on the trailing edge,
/// in a bubble as wide as the wider of the two.
private struct TextWithFooter: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(proposal) }
        let height = sizes.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: sizes.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let isFooter = index > 0
            subview.place(at: CGPoint(x: isFooter ? bounds.maxX : bounds.minX, y: y),
                          anchor: isFooter ? .topTrailing : .topLeading,
                          proposal: ProposedViewSize(size))
            y += size.height + spacing
        }
    }
}

/// Prose wraps into a readable column; columns (ls, tables) keep the width
/// they were laid out for.
private struct OutputWidth: ViewModifier {
    let isColumns: Bool

    func body(content: Content) -> some View {
        if isColumns {
            content
                .padding(.trailing, Metrics.bubbleOppositeInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content.bubbleWidth(0.8, alignment: .leading)
        }
    }
}
