import SwiftUI

/// The reply while a command is still running.
struct LiveResponseView: View {
    let live: LiveOutput
    let shell: ShellSession

    /// Quick commands skip the busy state entirely, so nothing flashes.
    @State private var showsBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            if live.isInteractive {
                InteractiveTerminalCard(live: live, shell: shell)
            } else if live.hasOutput {
                LiveOutputBubble(live: live)
            } else if showsBusy {
                TypingIndicator()
                    .transition(.opacity)
            }
            if showsBusy || live.hasOutput || live.isInteractive {
                RunningFooter(live: live)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            try? await Task.sleep(for: Metrics.busyStateDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) { showsBusy = true }
        }
    }
}
