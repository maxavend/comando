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
    @Environment(\.transcriptHeight) private var transcriptHeight
    @State private var isHovering = false
    @State private var textHeight: CGFloat = 0
    /// 0 folded, 1 open as far as the eye can see; animated.
    @State private var openness: CGFloat = 0
    /// Open all the way, past what fits on screen.
    @State private var isFullyOpen = false
    @State private var foldGeneration = 0

    /// Long output folds to the height of its last rows, which is usually
    /// where the result or the error is, and which follow along while it runs.
    /// Counted in rows, not lines, so a few long lines that wrap fold too.
    static let foldThreshold = 24
    static let foldedRows = 10

    var body: some View {
        let lineHeight = Metrics.singleLineBubbleHeight(fontSize: fontSize, monospaced: monospaced) - Metrics.bubbleVerticalPadding * 2
        let isFoldable = lineCount != nil
            && ((lineCount ?? 0) > Self.foldThreshold || textHeight > lineHeight * CGFloat(Self.foldThreshold) * 0.7)
        let folded = min(textHeight, lineHeight * CGFloat(Self.foldedRows))
        let fold = Fold(
            isActive: isFoldable && textHeight > 0,
            folded: folded,
            open: textHeight,
            // What moves on screen: at most the transcript's height. The rest
            // of a long output is added (or removed) at once, out of view.
            onScreen: min(textHeight, max(folded, transcriptHeight)),
            isFullyOpen: isFullyOpen,
            openness: openness
        )
        let firstLineCenter = Metrics.singleLineBubbleHeight(fontSize: fontSize, monospaced: monospaced) / 2
        TextWithFooter(spacing: Metrics.bubbleVerticalPadding) {
            LinkAwareText(content: output)
                .font(.system(size: fontSize, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
                .modifier(FoldWindow(fold: fold))
            if isFoldable {
                // One link: unfold here; when even that is cut short, the
                // whole output opens in a window.
                HStack(spacing: Metrics.bubbleHorizontalPadding) {
                    if openness > 0, let onShowAll {
                        Button("Ver todo", action: onShowAll)
                    }
                    Button(openness > 0 ? "Ver menos" : "Ver más", action: toggle)
                }
                .buttonStyle(.link)
                .pointerStyle(.link)
                .foregroundStyle(.tint)
                // The links change at once; only the bubble moves.
                .transaction { $0.animation = nil }
            }
        }
        .bubble(.reply)
        .bubbleAccessory(on: .trailing, firstLineCenter: firstLineCenter, isHovering: $isHovering) {
            CopyButton(text: plainText)
        }
        #if DEBUG
        .onDebugAction("#fold") { _ in toggle() }
        #endif
        .modifier(OutputWidth(isColumns: monospaced))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Salida")
    }

    /// A spring, like a disclosure in Apple's apps, over the stretch you can
    /// see: opening, the rows above the fold come down into view (at the
    /// bottom of the transcript, what's above moves up with them) and the
    /// rest is added out of sight; closing does the reverse.
    private func toggle() {
        foldGeneration += 1
        let generation = foldGeneration
        var duration = 0.45
        #if DEBUG
        duration *= DebugAutomation.slowMotion
        #endif
        if openness == 0 {
            withAnimation(.smooth(duration: duration)) { openness = 1 } completion: {
                if generation == foldGeneration { isFullyOpen = true }
            }
        } else {
            isFullyOpen = false
            withAnimation(.smooth(duration: duration)) { openness = 0 }
        }
    }
}

/// How a long output is folded right now.
private struct Fold {
    var isActive: Bool
    var folded: CGFloat
    var open: CGFloat
    var onScreen: CGFloat
    var isFullyOpen: Bool
    var openness: CGFloat

    var visible: CGFloat { isFullyOpen ? open : folded + (onScreen - folded) * openness }
}

/// The window over the text: its last rows, growing upward as it opens, with
/// the rows above the fold fading out while it's closed. Animatable, so the
/// transcript lays it out on every frame and keeps up with it.
private struct FoldWindow: ViewModifier, Animatable {
    var fold: Fold

    var animatableData: CGFloat {
        get { fold.openness }
        set { fold.openness = newValue }
    }

    func body(content: Content) -> some View {
        if fold.isActive {
            let fade = fold.open > fold.folded + 1 ? 1 - fold.openness : 0
            content
                .frame(height: fold.visible, alignment: .bottom)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .black.opacity(1 - fade), location: 0),
                                           .init(color: .black, location: 0.25 * fade)],
                                   startPoint: .top, endPoint: .bottom)
                }
        } else {
            content
        }
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
