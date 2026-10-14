import SwiftUI

/// What a command does, in plain words, under its bubble.
struct CommandDescription: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: Metrics.statusLineHeight)
            .padding(.trailing, Metrics.bubbleHorizontalPadding)
    }
}
