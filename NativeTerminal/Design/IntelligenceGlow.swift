import SwiftUI

/// The Apple Intelligence glow: the spectrum running around a shape's edge as
/// soft light, slowly turning and breathing like Siri listening. The light is
/// strongest at the edge and fades smoothly inward, leaving only a faint tint
/// in the middle: no line, no hard band. Still with Reduce Motion.
struct IntelligenceGlow<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool
    /// How far the light reaches inward, in points.
    var depth: CGFloat = 12
    /// How much tint is left in the middle, from 0 to 1.
    var centerTint: Double = 0.18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Seconds per full turn of the colors.
    private static var period: Double { 5 }

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(time.truncatingRemainder(dividingBy: Self.period) / Self.period * 360)
            let breath = reduceMotion ? 1 : 0.85 + 0.15 * sin(time * 2)
            shape
                .fill(AngularGradient(colors: IntelligenceGlyph.spectrum, center: .center, angle: angle))
                // Softens where the colors meet, so they flow into each other.
                .blur(radius: depth * 0.35)
                .saturation(1.5)
                .mask(EdgeFalloff(shape: shape, depth: depth, centerTint: centerTint))
                .opacity(breath)
        }
        // On dark glass the colors add light instead of covering it.
        .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        .opacity(isActive ? 1 : 0)
        .animation(.smooth(duration: 0.5), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Opaque at the shape's edge, fading smoothly to `centerTint` toward the
/// middle: a blurred inner copy of the shape, read as an alpha mask.
private struct EdgeFalloff<S: InsettableShape>: View {
    let shape: S
    let depth: CGFloat
    let centerTint: Double

    var body: some View {
        ZStack {
            shape.fill(.white)
            shape.inset(by: depth * 0.6)
                .fill(Color(white: centerTint))
                .blur(radius: depth * 0.6)
        }
        .compositingGroup()
        .luminanceToAlpha()
    }
}
