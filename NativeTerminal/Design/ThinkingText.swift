import SwiftUI

/// A status line that cycles through states while work is in progress: a
/// shimmer sweeps the glyphs, and each new state rises in from below while
/// the old one drifts up and blurs away. Still text with Reduce Motion.
struct ThinkingText: View {
    let states: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private enum Timing {
        static let hold: Duration = .seconds(2)
        static let swap = 0.15
        static let gap = 0.05
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // The longest state sizes the box, so it never resizes mid-swap.
            Text(longest).hidden()
            ShimmerText(text: current, isAnimated: !reduceMotion)
                .id(index)
                .transition(reduceMotion ? AnyTransition.identity : AnyTransition(Self.swap))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current)
        .accessibilityAddTraits(.updatesFrequently)
        .task(id: states) {
            index = 0
            guard states.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Timing.hold)
                guard !Task.isCancelled else { return }
                // Stops on the last state instead of looping back to the first.
                guard index < states.count - 1 else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Timing.swap)) { index += 1 }
            }
        }
    }

    private var current: String { states.isEmpty ? "" : states[min(index, states.count - 1)] }
    private var longest: String { states.max { $0.count < $1.count } ?? "" }

    private static var swap: some Transition {
        AsymmetricTransition(
            insertion: ThinkingSwap(distance: 8).animation(.easeInOut(duration: Timing.swap).delay(Timing.gap)),
            removal: ThinkingSwap(distance: -8)
        )
    }
}

/// Offset, blur and fade away from rest; `distance` is where the text sits
/// when hidden (positive: below).
private struct ThinkingSwap: Transition {
    let distance: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(y: phase.isIdentity ? 0 : distance)
            .blur(radius: phase.isIdentity ? 0 : 2)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// Secondary text with a highlight sweeping across its glyphs.
private struct ShimmerText: View {
    let text: String
    let isAnimated: Bool

    private static let period = 2.0

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .overlay {
                if isAnimated {
                    TimelineView(.animation) { context in
                        let progress = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: Self.period) / Self.period
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            // A band four times as wide as the text slides from
                            // left to right, so the highlight enters and leaves
                            // off the edges.
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.4),
                                    .init(color: .primary, location: 0.5),
                                    .init(color: .clear, location: 0.6),
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: width * 4)
                            .offset(x: -3 * width + progress * 3 * width)
                        }
                        .mask(Text(text).lineLimit(1))
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}
