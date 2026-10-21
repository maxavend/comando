import SwiftUI

struct SessionRow: View {
    let session: TerminalSession
    let shell: ShellSession?

    @Environment(TerminalController.self) private var controller

    private var isRunning: Bool { shell?.isBusy ?? false }
    /// Running, or an agent conversation open and ready: the avatar's green dot.
    private var isOnline: Bool { isRunning || controller.agentChats[session.id]?.isReady == true }

    /// The last command, or the last request to the assistant with its star
    /// (stored as “✨ ” before the request).
    private var lastLine: Text {
        guard let last = session.lastCommand else { return Text(FolderName.breadcrumb(session.directory)) }
        guard last.hasPrefix("✨ ") else { return Text(last) }
        return Text("\(Image(systemName: "sparkle")) \(String(last.dropFirst(2)))")
    }

    var body: some View {
        let live = shell?.live
        HStack(spacing: 0) {
            SessionAvatar(isRunning: isOnline, emoji: session.emoji, colorIndex: session.colorIndex,
                          symbol: session.avatarSymbol(for: session.directory))
                .padding(.trailing, Metrics.sidebarRowSpacing)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.timestamp(for: session.lastActivity))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // Running is said once, by the avatar's dot: this line shows only what runs.
                Group {
                    if let live {
                        Text(Self.activity(live))
                            .lineLimit(1)
                    } else {
                        lastLine
                            .lineLimit(2)
                    }
                }
                .font(.body)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Metrics.sidebarRowVerticalPadding)
        // The separator starts under the text, not under the avatar.
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            Metrics.avatarSize + Metrics.sidebarRowSpacing
        }
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

    /// What a running session is doing, in place of its last command: the
    /// address it serves, or the command itself.
    static func activity(_ live: LiveOutput) -> String {
        if let url = live.localURL, let host = url.host {
            return host + (url.port.map { ":\($0)" } ?? "")
        }
        return live.command
    }
}
