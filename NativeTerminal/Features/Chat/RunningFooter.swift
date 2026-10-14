import SwiftUI

/// Status under a reply that is still running.
///
/// While output keeps coming it reads “Ejecutando”. Once a command goes quiet
/// (a dev server waiting for requests, a program waiting for input) it reads
/// “Sigue activo” instead of spinning forever, and offers to stop it.
struct RunningFooter: View {
    let live: LiveOutput
    let shell: ShellSession

    /// Seconds without output before a command counts as idle.
    private static let quietAfter: TimeInterval = 4

    var body: some View {
        TimelineView(.periodic(from: live.startedAt, by: 1)) { context in
            let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(live.startedAt)))
            let isQuiet = live.hasOutput && context.date.timeIntervalSince(live.lastOutputAt) > Self.quietAfter
            StatusLine {
                if isQuiet {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text("Sigue activo · \(elapsed.formatted(.time(pattern: .minuteSecond)))")
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Ejecutando · \(elapsed.formatted(.time(pattern: .minuteSecond)))")
                        .monospacedDigit()
                }
                if let url = live.localURL {
                    Text("·")
                    Link("Abrir en el navegador", destination: url)
                        .foregroundStyle(.tint)
                        .help(url.absoluteString)
                }
                if isQuiet {
                    Text("·")
                    Button("Detener", action: stop)
                        .buttonStyle(.link)
                        .foregroundStyle(.tint)
                        .help("Detener el comando (⌘.)")
                }
            }
        }
    }

    private func stop() {
        shell.interrupt()
    }
}
