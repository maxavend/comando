import SwiftUI

/// A native progress bar for commands that redraw a progress line (downloads,
/// installs, builds), instead of text that keeps rewriting itself.
struct ProgressBubble: View {
    let progress: ProgressParser.Progress

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing + 2) {
            Text(progress.label)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: progress.fraction)
                .frame(width: 280)
                .animation(.linear(duration: 0.1), value: progress.fraction)
                .accessibilityValue(Text(progress.fraction, format: .percent.precision(.fractionLength(0))))
        }
        .bubble(.reply)
        .padding(.trailing, Metrics.bubbleOppositeInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
