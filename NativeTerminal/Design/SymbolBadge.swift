import SwiftUI

/// An SF Symbol in a tinted glass circle, used for hero artwork
/// (welcome guide, empty session).
struct SymbolBadge: View {
    let systemImage: String
    var size: CGFloat = 88

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .circle)
            .accessibilityHidden(true)
    }
}
