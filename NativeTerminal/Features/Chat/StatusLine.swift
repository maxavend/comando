import SwiftUI

/// The small line under a reply (“Delivered” in Messages). Shared by running
/// and finished commands so the layout doesn't shift when a command ends.
struct StatusLine<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(height: Metrics.statusLineHeight)
        .padding(.leading, Metrics.bubbleHorizontalPadding)
        .accessibilityElement(children: .combine)
    }
}
