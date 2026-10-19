import SwiftUI

/// The bubble from the app icon, on its own: the blue speech bubble with the
/// `>_` prompt, drawn from the same shapes as `AppIcon.icon`.
struct AppBubble: View {
    var size: CGFloat = 96

    static let blue = Color(red: 0.10, green: 0.49, blue: 1.0)

    var body: some View {
        ZStack {
            BubbleOutline()
                .fill(
                    LinearGradient(
                        colors: [Self.blue.mix(with: .white, by: 0.18), Self.blue],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                // A soft light along the top edge, like the icon's glass.
                .overlay {
                    BubbleOutline()
                        .stroke(
                            LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center),
                            lineWidth: size * 0.02
                        )
                }
            PromptGlyph()
                .stroke(.white, style: StrokeStyle(lineWidth: size * Self.scale * 44, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Points of the 1024-point icon canvas per point of this view.
    fileprivate static let scale: CGFloat = 1 / IconCanvas.side
}

/// The bubble drawn like an SF Symbol: the outline and the prompt in one
/// color, with a stroke as heavy as a medium-weight symbol, so it sits among
/// symbols without standing out.
struct AppBubbleSymbol: View {
    var size: CGFloat = 40

    var body: some View {
        // About the stroke of a medium-weight symbol at this size.
        let line = size * 0.075
        ZStack {
            BubbleOutline()
                .stroke(style: StrokeStyle(lineWidth: line, lineJoin: .round))
            // The prompt where the app icon has it.
            PromptGlyph()
                .stroke(style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
        // Keeps the stroke inside the frame.
        .padding(line / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The part of the 1024-point icon canvas the bubble covers, as a square.
private nonisolated enum IconCanvas {
    static let origin = CGPoint(x: 196, y: 160)
    static let side: CGFloat = 632

    /// Maps a point of the icon canvas into `rect`.
    static func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (x - origin.x) / side * rect.width,
            y: rect.minY + (y - origin.y) / side * rect.height
        )
    }
}

/// The round bubble with its tail at the bottom right.
private nonisolated struct BubbleOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { IconCanvas.point(x, y, in: rect) }
        let radius = 300 / IconCanvas.side * rect.width
        let circle = Path(ellipseIn: CGRect(x: p(512, 462).x - radius, y: p(512, 462).y - radius, width: radius * 2, height: radius * 2))
        var tail = Path()
        tail.move(to: p(612, 724))
        tail.addCurve(to: p(780, 786), control1: p(652, 768), control2: p(714, 790))
        tail.addCurve(to: p(742, 628), control1: p(748, 750), control2: p(738, 690))
        tail.closeSubpath()
        // One outline, so no seam shows where the tail meets the circle.
        return circle.union(tail)
    }
}

/// The `>_` prompt.
private nonisolated struct PromptGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { IconCanvas.point(x, y, in: rect) }
        var path = Path()
        path.move(to: p(348, 318))
        path.addLine(to: p(420, 374))
        path.addLine(to: p(348, 430))
        path.move(to: p(458, 430))
        path.addLine(to: p(526, 430))
        return path
    }
}

#Preview {
    AppBubble(size: 120).padding(40)
}
