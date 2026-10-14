import SwiftUI

/// Status under a reply that is still running. Stopping lives in the composer
/// and the Shell menu, so this stays as quiet as a receipt.
struct RunningFooter: View {
    let live: LiveOutput

    var body: some View {
        StatusLine {
            ProgressView()
                .controlSize(.mini)
            TimelineView(.periodic(from: live.startedAt, by: 1)) { context in
                let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(live.startedAt)))
                Text("Ejecutando · \(elapsed.formatted(.time(pattern: .minuteSecond)))")
                    .monospacedDigit()
            }
        }
    }
}
