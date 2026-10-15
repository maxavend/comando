import SwiftUI

/// The Apple Intelligence glow: the spectrum running around a shape's edge,
/// with a crisp line and soft halos that slowly turn and breathe, like Siri
/// listening. When it turns on, the light first sweeps around the edge.
/// Still (and without the sweep) with Reduce Motion.
struct IntelligenceGlow<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool
    /// How far the halo spreads: small for a field, large for a window.
    var spread: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// How much of the edge is lit, from 0 to 1, while it sweeps in.
    @State private var drawn: CGFloat = 0

    /// Seconds per full turn of the colors.
    private static var period: Double { 4 }

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(time.truncatingRemainder(dividingBy: Self.period) / Self.period * 360)
            let breath = reduceMotion ? 1 : 0.8 + 0.2 * sin(time * 2.2)
            let gradient = AngularGradient(colors: IntelligenceGlyph.spectrum, center: .center, angle: angle)
            ZStack {
                // Wide, faint halo.
                edge(lineWidth: 14 * spread).stroke(gradient, lineWidth: 14 * spread)
                    .blur(radius: 18 * spread)
                    .opacity(0.45 * breath)
                // Closer glow.
                edge(lineWidth: 5 * spread).stroke(gradient, lineWidth: 5 * spread)
                    .blur(radius: 5 * spread)
                    .opacity(0.8 * breath)
                // The crisp edge.
                edge(lineWidth: 1.5).stroke(gradient, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .opacity(colorScheme == .dark ? 0.95 : 0.85)
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.smooth(duration: 0.45), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isActive, initial: true) { _, active in
            guard active else {
                drawn = 0
                return
            }
            if reduceMotion {
                drawn = 1
            } else {
                drawn = 0
                withAnimation(.easeOut(duration: 0.7)) { drawn = 1 }
            }
        }
    }

    /// The shape inset so a stroke of `lineWidth` stays inside it, trimmed to
    /// the part lit so far. Both ends grow from the top, meeting at the bottom.
    private func edge(lineWidth: CGFloat) -> some Shape {
        SweepShape(base: shape.inset(by: lineWidth / 2), drawn: drawn)
    }
}

/// Lights a shape's outline from the middle of its top edge outward in both
/// directions, as `drawn` goes from 0 to 1.
nonisolated private struct SweepShape<Base: Shape>: Shape {
    var base: Base
    var drawn: CGFloat

    var animatableData: CGFloat {
        get { drawn }
        set { drawn = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let outline = base.path(in: rect)
        guard drawn < 1 else { return outline }
        // Rounded rectangles start their outline at the top-right corner; the
        // top middle sits just before it, near the end of the path.
        let start: CGFloat = 0.97
        let half = drawn / 2
        var path = Path()
        path.addPath(outline.trimmedPath(from: max(0, start - half), to: start))
        path.addPath(outline.trimmedPath(from: start, to: min(1, start + half)))
        if start + half > 1 {
            path.addPath(outline.trimmedPath(from: 0, to: start + half - 1))
        }
        return path
    }
}
