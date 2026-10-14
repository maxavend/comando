import SwiftUI

/// The Apple Intelligence symbol in its spectrum colors. While `isActive`,
/// the colors swirl around it and the symbol breathes, a small sign that the
/// model is working. Still with Reduce Motion.
struct IntelligenceGlyph: View {
    var isActive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per full turn of the colors.
    private static let period = 2.4
    private static let spectrum: [Color] = [
        Color(red: 0.18, green: 0.55, blue: 1.00), // blue
        Color(red: 0.64, green: 0.36, blue: 1.00), // purple
        Color(red: 1.00, green: 0.31, blue: 0.64), // pink
        Color(red: 1.00, green: 0.54, blue: 0.24), // orange
        Color(red: 1.00, green: 0.78, blue: 0.25), // yellow
        Color(red: 0.18, green: 0.55, blue: 1.00), // back to blue, seamless
    ]

    private var animates: Bool { isActive && !reduceMotion }

    var body: some View {
        TimelineView(.animation(paused: !animates)) { context in
            let turn = animates
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                : 0
            Image(systemName: "apple.intelligence")
                .foregroundStyle(AngularGradient(colors: Self.spectrum, center: .center, angle: .degrees(turn * 360)))
                .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous), isActive: animates)
                .shadow(color: Self.spectrum[1].opacity(animates ? 0.45 : 0), radius: 3)
        }
        .accessibilityHidden(true)
    }
}
