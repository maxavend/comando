import SwiftUI

struct SessionRow: View {
    let session: TerminalSession
    let isRunning: Bool

    var body: some View {
        HStack(spacing: Metrics.sidebarRowSpacing) {
            SessionAvatar(isRunning: isRunning)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // Running state is shown on the avatar, so the row never changes shape.
                    Text(Self.timestamp(for: session.lastActivity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(session.lastCommand ?? FolderName.breadcrumb(session.directory))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Metrics.sidebarRowVerticalPadding)
        .badge(session.unreadCount)
        .help(FolderName.breadcrumb(session.directory))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRunning ? Text("En ejecución") : Text(""))
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
