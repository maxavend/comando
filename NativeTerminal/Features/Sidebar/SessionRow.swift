import SwiftUI

struct SessionRow: View {
    let session: TerminalSession
    let shell: ShellSession?

    private var isRunning: Bool { shell?.isBusy ?? false }

    /// The last command, or the last request to the assistant with its star
    /// (stored as “✨ ” before the request).
    private var lastLine: Text {
        guard let last = session.lastCommand else { return Text(FolderName.breadcrumb(session.directory)) }
        guard last.hasPrefix("✨ ") else { return Text(last) }
        return Text("\(Image(systemName: "sparkle")) \(String(last.dropFirst(2)))")
    }

    var body: some View {
        let live = shell?.live
        HStack(spacing: Metrics.sidebarRowSpacing) {
            SessionAvatar(isRunning: isRunning, emoji: session.emoji, colorIndex: session.colorIndex)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // Both trailing items use the caption size, so the row never changes shape.
                    if isRunning {
                        Button("Detener", systemImage: "stop.circle.fill", action: stop)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Detener el comando")
                    } else {
                        Text(Self.timestamp(for: session.lastActivity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let live {
                    ActivityLine(live: live)
                } else {
                    lastLine
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, Metrics.sidebarRowVerticalPadding)
        .badge(session.unreadCount)
        .help(FolderName.breadcrumb(session.directory))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRunning ? Text("En ejecución") : Text(""))
    }

    private func stop() {
        shell?.interrupt()
    }

    /// Messages-style timestamps: time today, “Ayer”, then the date.
    static func timestamp(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Ayer")
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

/// What a running session is doing, in place of its last command.
private struct ActivityLine: View {
    let live: LiveOutput

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(activity)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var activity: String {
        if let url = live.localURL, let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            return String(localized: "Activo · \(host)\(port)")
        }
        return String(localized: "Ejecutando: \(live.command)")
    }
}
