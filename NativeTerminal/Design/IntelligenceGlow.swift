import SwiftUI

/// The Apple Intelligence edge light: a thin line on a shape's edge where
/// arcs of the spectrum travel like comets, with a soft glow only outside.
/// The inside stays clean. While working, only the glow grows a little and
/// breathes. Still with Reduce Motion.
struct IntelligenceGlow<S: InsettableShape>: View {
    let shape: S
    var isActive: Bool
    /// The request is out: the glow grows a little and breathes.
    var isWorking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var clock = GlowClock()

    var body: some View {
        TimelineView(.animation(paused: !isActive || reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let state = reduceMotion ? GlowClock.State.still : clock.advance(to: time, working: isWorking)
            ZStack {
                // No outline of its own: the tips fade into the field's own rim.
                // The glow, only outside: it lights the surroundings, not the text.
                // While working only the glow grows, breathing softly.
                arcs(state, lineWidth: 5, taper: 2.2)
                    .blur(radius: 6 + 2 * state.energy)
                    .opacity(0.45 + 0.25 * state.energy * (0.7 + 0.3 * sin(state.wave * 1.6)))
                    .mask(Outside(shape: shape))
                // The line itself: one pixel, crisp, right on the edge.
                arcs(state, lineWidth: 1, taper: 1.2)
            }
            .saturation(1.45)
        }
        .compositingGroup()
        // On dark glass the light adds to it instead of covering it.
        .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        .opacity(isActive ? 1 : 0)
        .animation(.smooth(duration: 0.5), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Two comets on opposite sides of the edge, each a run of the spectrum
    /// that fades in and out. Drawn as short pieces of the outline, so they
    /// move at the same speed all the way around, corners included.
    /// `taper` sets how early the tips fade: higher fades them sooner.
    private func arcs(_ state: GlowClock.State, lineWidth: CGFloat, taper: Double) -> some View {
        ZStack {
            ForEach(Array(Self.comets.enumerated()), id: \.offset) { index, colors in
                let i = Double(index)
                // Each comet keeps its own slow rhythm: it stretches and
                // shrinks, and drifts a little ahead of or behind the other.
                let stretch = 0.22 * sin(state.wave * (0.55 + 0.17 * i) + i * 2.1)
                    + 0.08 * sin(state.wave * (1.3 - 0.2 * i) + i)
                let length = state.length * (1 + stretch)
                let drift = 0.035 * sin(state.wave * (0.31 + 0.11 * i) + i * 1.7)
                let start = state.phase + i / Double(Self.comets.count) + drift
                ForEach(0..<Self.pieces, id: \.self) { piece in
                    let position = Double(piece) / Double(Self.pieces - 1)
                    let from = start + position * length
                    // Brightest in the middle, melting away toward both tips.
                    let fade = pow(sin(position * .pi), taper)
                    WrappedTrim(shape: shape, from: from, to: from + length / Double(Self.pieces - 1))
                        .stroke(Self.color(in: colors, at: position).opacity(fade * state.brightness),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
            }
        }
    }

    private static var pieces: Int { 36 }
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

/// Keeps the light's motion continuous: speed and energy ease toward their
/// targets instead of jumping, so the light never skips when the state
/// changes.
@MainActor
private final class GlowClock {
    struct State {
        var phase: Double
        /// 0 calm, 1 working.
        var energy: Double
        var wave: Double
        var length: Double { 0.32 }
        var brightness: Double { 0.95 }

        static let still = State(phase: 0.1, energy: 0, wave: 0)
    }

    private var last: Double?
    private var phase = 0.0
    private var energy = 0.0
    private var wave = 0.0

    func advance(to time: Double, working: Bool) -> State {
        let delta = min(max(time - (last ?? time), 0), 0.1)
        last = time
        // Ease the energy over about a second.
        energy += ((working ? 1 : 0) - energy) * min(1, delta * 2.2)
        // A turn every 9 s, the same whether calm or working.
        phase = (phase + delta / 9).truncatingRemainder(dividingBy: 1)
        wave += delta * 1.3
        return State(phase: phase, energy: energy, wave: wave)
    }
}

/// Everything but the shape: keeps the glow outside it.
private struct Outside<S: Shape>: View {
    let shape: S

    var body: some View {
        Rectangle()
            .padding(-24)
            .overlay { shape.fill(.black).blendMode(.destinationOut) }
            .compositingGroup()
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
        let start = from.truncatingRemainder(dividingBy: 1)
        let end = start + (to - from)
        guard end > 1 else { return outline.trimmedPath(from: start, to: end) }
        var path = outline.trimmedPath(from: start, to: 1)
        path.addPath(outline.trimmedPath(from: 0, to: min(end - 1, 1)))
        return path
    }
}
