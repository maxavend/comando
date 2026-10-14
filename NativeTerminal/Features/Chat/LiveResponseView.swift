import AppKit
import SwiftTerm
import SwiftUI

/// The reply bubble while a command is still running.
struct LiveResponseView: View {
    let live: LiveOutput
    let shell: ShellSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if live.isInteractive {
                InteractiveTerminalCard(live: live, shell: shell)
            } else if live.hasOutput {
                LiveOutputBubble(live: live)
            } else {
                TypingIndicator()
            }
            RunningFooter(live: live, shell: shell)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
