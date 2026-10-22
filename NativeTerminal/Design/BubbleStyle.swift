import SwiftUI

enum BubbleRole {
    /// What the user sent: accent-filled, on the trailing side.
    case command
    /// What the shell answered: neutral fill, on the leading side.
    case reply
    /// A request in words for the assistant: on the trailing side, filled
    /// with a blue-to-violet blend so it reads apart from commands.
    case request
}

extension View {
    /// Applies the shared bubble padding, fill and shape. The tail marks the
    /// last bubble of a run from the same side, like Messages.
    func bubble(_ role: BubbleRole, tail: Bool = false) -> some View {
        let shape = BubbleShape(side: role == .reply ? .leading : .trailing, hasTail: tail)
        return padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.vertical, Metrics.bubbleVerticalPadding)
            .background {
                if role == .request {
                    ScrollTintedFill(shape: shape)
                } else {
                    shape.fill(fill(for: role))
                }
            }
    }

    /// Caps a bubble's width at a share of the transcript, so long text wraps
    /// into a readable column instead of spanning the window.
    func bubbleWidth(_ fraction: CGFloat, alignment: Alignment) -> some View {
        containerRelativeFrame(.horizontal, alignment: alignment) { length, _ in length * fraction }
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private func fill(for role: BubbleRole) -> AnyShapeStyle {
    switch role {
    case .command: AnyShapeStyle(.tint)
    case .reply: AnyShapeStyle(.fill.secondary)
    case .request: AnyShapeStyle(LinearGradient(colors: [.accentColor, IntelligenceGlyph.violet],
                                                startPoint: .leading, endPoint: .trailing))
    }
}

/// The blue-to-violet blend of requests to the assistant, shifting with the
/// bubble's height on screen like Messages: bluer at the bottom, where new
/// messages arrive, and toward violet and pink as it scrolls up.
private struct ScrollTintedFill: View {
    let shape: BubbleShape

    var body: some View {
        shape
            .fill(LinearGradient(colors: [.accentColor, IntelligenceGlyph.violet], startPoint: .leading, endPoint: .trailing))
            .visualEffect { content, proxy in
                let frame = proxy.frame(in: .scrollView)
                let height = proxy.bounds(of: .scrollView)?.height ?? frame.maxY
                let position = height > 0 ? min(max(frame.midY / height, 0), 1) : 1
                // 0 at the top, 1 at the bottom: up to 45° of hue toward pink.
                return content.hueRotation(.degrees((1 - position) * 45))
            }
    }
}

/// A rounded bubble — a pill when it holds one line — with an optional tail
/// curling out of its bottom corner. Drawn as one path, so a translucent fill
/// doesn't darken where the tail meets the body.
nonisolated struct BubbleShape: Shape {
    enum Side { case leading, trailing }

    var side: Side
    var hasTail = true

    /// How far the tail reaches past the bubble's edge.
    static let tailReach: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let radius = min(Metrics.bubbleCornerRadius, rect.height / 2)
        let body = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        guard hasTail else { return body }

        // Drawn for the trailing side, then mirrored for the leading one: the
        // edge runs down, flares into a point past the corner, and curves back
        // under the bubble, like Messages.
        let width = rect.width, height = rect.height
        let reach = Self.tailReach
        let attach = min(13, height * 0.45)
        var tail = Path()
        tail.move(to: CGPoint(x: width, y: height - attach))
        tail.addCurve(
            to: CGPoint(x: width + reach, y: height),
            control1: CGPoint(x: width, y: height - attach * 0.3),
            control2: CGPoint(x: width + reach * 0.35, y: height - 0.6)
        )
        tail.addQuadCurve(
            to: CGPoint(x: width - 9, y: height - 2.5),
            control: CGPoint(x: width - 1.5, y: height + 0.6)
        )
        tail.addLine(to: CGPoint(x: width - attach, y: height - attach))
        tail.closeSubpath()

        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        if side == .leading {
            transform = transform.translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        }
        return body.union(tail.applying(transform))
    }
}

extension View {
    /// Shows `accessory` (a copy button) just outside the bubble, centered on
    /// its first line, while the pointer is over the bubble; `beside` sits
    /// further out and shows itself from `isHovering`.
    ///
    /// Like the safe triangle of a submenu, the pointer can cut across to the
    /// accessory from anywhere on the bubble: the strip between them, as tall
    /// as the bubble, counts as the bubble, and leaving waits a moment. Only
    /// one bubble shows its accessory: the next one hovered takes over at once.
    func bubbleAccessory<Accessory: View, Beside: View>(
        on edge: HorizontalEdge,
        firstLineCenter: CGFloat,
        isHovering: Binding<Bool>,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder beside: () -> Beside = { EmptyView() }
    ) -> some View {
        modifier(BubbleAccessory(edge: edge, firstLineCenter: firstLineCenter, isHovering: isHovering,
                                 accessory: accessory(), beside: beside()))
    }
}

private struct BubbleAccessory<Accessory: View, Beside: View>: ViewModifier {
    let edge: HorizontalEdge
    let firstLineCenter: CGFloat
    @Binding var isHovering: Bool
    let accessory: Accessory
    let beside: Beside

    @State private var isOverBubble = false
    @State private var isOverStrip = false
    @State private var isOverAccessory = false
    @State private var accessoryWidth: CGFloat = 0
    @State private var leaving: Task<Void, Never>?
    @State private var id = UUID()
    private var owner = BubbleAccessoryOwner.shared

    private let gap = Metrics.replySpacing

    func body(content: Content) -> some View {
        let isLeading = edge == .leading
        content
            .onHover { isOverBubble = $0; update() }
            .overlay(alignment: isLeading ? .leading : .trailing) {
                Color.clear
                    .frame(width: gap + accessoryWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .onHover { isOverStrip = $0; update() }
                    .alignmentGuide(isLeading ? .leading : .trailing) { $0[isLeading ? .trailing : .leading] }
                    .accessibilityHidden(true)
            }
            .overlay(alignment: isLeading ? .topLeading : .topTrailing) {
                HStack(spacing: Metrics.composerSpacing) {
                    if isLeading { beside }
                    accessory
                        .opacity(isHovering ? 1 : 0)
                        .onHover { isOverAccessory = $0; update() }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { accessoryWidth = $0 }
                    if !isLeading { beside }
                }
                .alignmentGuide(isLeading ? .leading : .trailing) {
                    isLeading ? $0[.trailing] + gap : $0[.leading] - gap
                }
                .alignmentGuide(.top) { $0[VerticalAlignment.center] - firstLineCenter }
            }
            .onChange(of: owner.id) { _, newOwner in
                // Another bubble was hovered: give way without waiting.
                if newOwner != id {
                    leaving?.cancel()
                    isHovering = false
                }
            }
    }

    private func update() {
        leaving?.cancel()
        if isOverBubble || isOverStrip || isOverAccessory {
            owner.id = id
            isHovering = true
        } else {
            leaving = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                isHovering = false
                if owner.id == id { owner.id = nil }
            }
        }
    }
}

/// The bubble whose accessory is showing, so two never show at once.
@Observable
private final class BubbleAccessoryOwner {
    static let shared = BubbleAccessoryOwner()
    var id: UUID?
}

/// A sent message's words, drawn rather than shown as text: they lay out and
/// look like `Text`, but macOS doesn't treat them as text, so a right-click
/// on them opens the message's own menu instead of the system's text menu
/// (Pídele a Siri, Tipo de letra, Ortografía…), which says nothing about a
/// message that was already sent.
struct DrawnText: View {
    let string: String

    init(_ string: String) {
        self.string = string
    }

    var body: some View {
        // The hidden text gives the size; the canvas draws the same words in it.
        Text(string)
            .hidden()
            .overlay {
                Canvas { context, size in
                    var text = context.resolve(Text(string))
                    text.shading = .foreground
                    context.draw(text, in: CGRect(origin: .zero, size: size))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(string)
    }
}
