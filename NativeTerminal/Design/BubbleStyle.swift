import SwiftUI

enum BubbleRole {
    /// What the user sent: accent-filled, on the trailing side.
    case command
    /// What the shell answered: neutral fill, on the leading side.
    case reply
}

extension View {
    /// Applies the shared bubble padding, fill and shape.
    func bubble(_ role: BubbleRole) -> some View {
        padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.vertical, Metrics.bubbleVerticalPadding)
            .background(
                role == .command ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                in: .rect(cornerRadius: Metrics.bubbleCornerRadius)
            )
    }
}
