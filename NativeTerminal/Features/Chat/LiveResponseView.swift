import SwiftUI

/// The reply while a command is still running.
struct LiveResponseView: View {
    let live: LiveOutput
    let shell: ShellSession

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            if live.isInteractive {
                InteractiveTerminalCard(live: live, shell: shell)
            } else if live.hasOutput {
                LiveOutputBubble(live: live)
            } else {
                TypingIndicator()
            }
            RunningFooter(live: live)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
