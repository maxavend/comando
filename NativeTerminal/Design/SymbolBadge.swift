import SwiftUI

/// An SF Symbol in a tinted glass circle, used for hero artwork
/// (welcome guide, empty session).
struct SymbolBadge: View {
    let systemImage: String
    var size: CGFloat = 88

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * Self.contentScale, weight: .medium))
            .foregroundStyle(.tint)
            .badgeCircle(size: size)
    }

    /// How much of the circle the artwork takes.
    static let contentScale: CGFloat = 0.45
}

/// The app's bubble as a symbol, in the same glass circle as the other
/// badges.
struct AppBubbleBadge: View {
    var size: CGFloat = 88

    var body: some View {
        // A symbol's glyph runs a little wider than its point size; this
        // matches the bubble to it.
        AppBubbleSymbol(size: size * 0.55)
            .foregroundStyle(.tint)
            .badgeCircle(size: size)
    }
}

private extension View {
    func badgeCircle(size: CGFloat) -> some View {
        frame(width: size, height: size)
            .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .circle)
            .accessibilityHidden(true)
    }
}
