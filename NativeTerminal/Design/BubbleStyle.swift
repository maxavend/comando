import SwiftUI

enum BubbleRole {
    /// What the user sent: accent-filled, on the trailing side.
    case command
    /// What the shell answered: neutral fill, on the leading side.
    case reply
}

extension View {
    /// Applies the shared bubble padding, fill and shape. The tail marks the
    /// last bubble of a run from the same side, like Messages.
    func bubble(_ role: BubbleRole, tail: Bool = false) -> some View {
        padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.vertical, Metrics.bubbleVerticalPadding)
            .background(
                role == .command ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                in: BubbleShape(side: role == .command ? .trailing : .leading, hasTail: tail)
            )
    }

    /// Caps a bubble's width at a share of the transcript, so long text wraps
    /// into a readable column instead of spanning the window.
    func bubbleWidth(_ fraction: CGFloat, alignment: Alignment) -> some View {
        containerRelativeFrame(.horizontal, alignment: alignment) { length, _ in length * fraction }
            .frame(maxWidth: .infinity, alignment: alignment)
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
