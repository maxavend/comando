import AppKit
import SwiftTerm
import SwiftUI

struct RunningFooter: View {
    let live: LiveOutput
    let shell: ShellSession

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: live.startedAt, by: 1)) { context in
                let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(live.startedAt)))
                Label {
                    Text(elapsed.formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                } icon: {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Detener", systemImage: "stop.fill") {
                shell.interrupt()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Interrumpir el comando (⌘.)")

            if !live.isInteractive {
                Button("Abrir como terminal", systemImage: "macwindow") {
                    shell.openInTerminal()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Muestra este programa en una terminal completa")
            }
        }
        .padding(.leading, 6)
    }
}
