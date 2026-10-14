import SwiftUI

struct SessionRow: View {
    let session: TerminalSession
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            SessionAvatar(isRunning: isRunning)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("En ejecución")
                    } else {
                        Text(Self.timestamp(for: session.lastActivity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(session.lastCommand ?? ShellEscape.abbreviate(session.directory))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .badge(session.unreadCount)
        .help(ShellEscape.abbreviate(session.directory))
        .accessibilityElement(children: .combine)
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
