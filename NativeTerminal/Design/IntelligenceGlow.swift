import SwiftUI

/// The Apple Intelligence edge light: a thin line around a shape where arcs
/// of the spectrum travel along the edge like comets, with a soft glow just
/// outside them. The inside stays clean. Calm while active; brighter and
/// faster while working. Still with Reduce Motion.
struct IntelligenceGlow<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool
    /// The request is out: the light speeds up and glows more.
    var isWorking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Seconds for an arc to go once around the edge.
    private var period: Double { isWorking ? 2.6 : 7 }

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let phase = time.truncatingRemainder(dividingBy: period) / period
            ZStack {
                // The whole edge, faintly lit, so it never goes fully dark.
                shape.strokeBorder(IntelligenceGlyph.spectrum[0].opacity(0.18), lineWidth: 1)
                // The glow: the arcs, wider and blurred, spilling outside.
                arcs(phase: phase, lineWidth: isWorking ? 7 : 5)
                    .blur(radius: isWorking ? 8 : 5)
                    .opacity(isWorking ? 1 : 0.7)
                // A tight bloom right on the edge.
                arcs(phase: phase, lineWidth: 3)
                    .blur(radius: 1.5)
                    .opacity(0.8)
                // The line itself, crisp.
                arcs(phase: phase, lineWidth: isWorking ? 2 : 1.5)
            }
            .saturation(1.2)
        }
        .compositingGroup()
        // On dark glass the light adds to it instead of covering it.
        .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        .opacity(isActive ? 1 : 0)
        .animation(.smooth(duration: 0.4), value: isActive)
        .animation(.smooth(duration: 0.4), value: isWorking)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Two comets on opposite sides of the edge, each a run of the spectrum
    /// that fades in and out. Drawn as short pieces of the outline, so they
    /// move at the same speed all the way around, corners included.
    private func arcs(phase: Double, lineWidth: CGFloat) -> some View {
        ZStack {
            ForEach(Array(Self.comets.enumerated()), id: \.offset) { index, colors in
                let start = phase + Double(index) / Double(Self.comets.count)
                ForEach(0..<Self.pieces, id: \.self) { piece in
                    let position = Double(piece) / Double(Self.pieces - 1)
                    let from = start + position * Self.length
                    let color = Self.color(in: colors, at: position)
                    // Bright in the middle, fading to nothing at both tips.
                    let fade = sin(position * .pi)
                    // Flat ends that just meet, so the comet reads as one line.
                    trimmed(from: from, to: from + Self.length / Double(Self.pieces - 1) * 1.04)
                        .stroke(color.opacity(fade), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
            }
        }
    }

    /// A piece of the outline, wrapping past the start of the path.
    private func trimmed(from: Double, to: Double) -> some Shape {
        let start = from.truncatingRemainder(dividingBy: 1)
        let end = start + (to - from)
        return WrappedTrim(shape: shape.inset(by: 0.75), from: start, to: end)
    }

    private static var pieces: Int { 36 }
    /// How much of the edge one comet covers.
    private static var length: Double { 0.22 }
    private static var comets: [[Color]] {
        let c = IntelligenceGlyph.spectrum
        return [[c[0], c[1], c[2]], [c[3], c[4], c[0]]]
    }

    private static func color(in colors: [Color], at position: Double) -> Color {
        let scaled = position * Double(colors.count - 1)
        let index = min(Int(scaled), colors.count - 2)
        return colors[index].mix(with: colors[index + 1], by: scaled - Double(index))
    }
}

/// A trim of a closed shape that may run past its end and continue from the
/// start.
private nonisolated struct WrappedTrim<S: Shape>: Shape {
    let shape: S
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        let outline = shape.path(in: rect)
        guard to > 1 else { return outline.trimmedPath(from: from, to: to) }
        var path = outline.trimmedPath(from: from, to: 1)
        path.addPath(outline.trimmedPath(from: 0, to: min(to - 1, 1)))
        return path
    }
}
