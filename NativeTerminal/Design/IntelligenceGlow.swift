import SwiftUI

/// The Apple Intelligence glow: the spectrum running around a shape's edge,
/// with a crisp line and soft halos that slowly turn and breathe, like Siri
/// listening. Still (and dimmer) with Reduce Motion.
struct IntelligenceGlow<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool
    /// How far the halo spreads: small for a field, large for a window.
    var spread: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

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
                shape.strokeBorder(gradient, lineWidth: 14 * spread)
                    .blur(radius: 18 * spread)
                    .opacity(0.45 * breath)
                // Closer glow.
                shape.strokeBorder(gradient, lineWidth: 5 * spread)
                    .blur(radius: 5 * spread)
                    .opacity(0.8 * breath)
                // The crisp edge.
                shape.strokeBorder(gradient, lineWidth: 1.5)
                    .opacity(colorScheme == .dark ? 0.95 : 0.85)
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.smooth(duration: 0.45), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
