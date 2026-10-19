import SwiftUI

/// A ring of glowing dots that light up in turn, in the Apple Intelligence
/// colors, like the indicator Apple shows while its AI thinks. Still, with
/// every dot softly lit, under Reduce Motion.
struct IntelligenceSpinner: View {
    var size: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dots = 8
    /// Seconds for the light to go once around.
    private static let period = 1.1

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.period) / Self.period
            let still = reduceMotion
            Canvas { canvas, size in
                Self.draw(in: &canvas, area: CGRect(origin: .zero, size: size), turn: turn, still: still)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static func draw(in canvas: inout GraphicsContext, area: CGRect, turn: Double, still: Bool) {
        let radius = min(area.width, area.height) / 2
        let dotRadius = radius * 0.2
        let ring = radius - dotRadius
        let center = CGPoint(x: area.midX, y: area.midY)
        for index in 0..<Self.dots {
            let position = Double(index) / Double(Self.dots)
            // How far behind the lit head this dot is, from 0 to 1.
            let behind = (turn - position + 1).truncatingRemainder(dividingBy: 1)
            let light = still ? 0.7 : pow(1 - behind, 2.2)
            let angle = position * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + ring * cos(angle), y: center.y + ring * sin(angle))
            let scale = 0.55 + 0.45 * light
            let dot = CGRect(x: point.x - dotRadius * scale, y: point.y - dotRadius * scale,
                             width: dotRadius * 2 * scale, height: dotRadius * 2 * scale)
            let color = Self.color(at: position + turn * 0.5)
            // A soft halo around the brightest dots.
            canvas.drawLayer { layer in
                layer.addFilter(.blur(radius: dotRadius * 1.4))
                layer.fill(Path(ellipseIn: dot.insetBy(dx: -dotRadius * 0.6, dy: -dotRadius * 0.6)),
                           with: .color(color.opacity(0.55 * light)))
            }
            canvas.fill(Path(ellipseIn: dot),
                        with: .color(Color.white.mix(with: color, by: 0.35).opacity(0.25 + 0.75 * light)))
        }
    }

    private static func color(at position: Double) -> Color {
        let spectrum = IntelligenceGlyph.spectrum
        let scaled = position.truncatingRemainder(dividingBy: 1) * Double(spectrum.count - 1)
        let index = min(Int(scaled), spectrum.count - 2)
        return spectrum[index].mix(with: spectrum[index + 1], by: scaled - Double(index))
    }
}

#Preview {
    IntelligenceSpinner(size: 40).padding(40).background(.black)
}
