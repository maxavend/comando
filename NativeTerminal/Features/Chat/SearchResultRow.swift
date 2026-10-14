import SwiftUI

struct SearchResultRow: View {
    let entry: CommandEntry
    let query: String
    let showsSession: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.command)
                    .font(.body.monospaced())
                    .lineLimit(1)
                Spacer()
                Text(entry.startedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let snippet {
                Text(snippet)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if showsSession, let session = entry.session {
                Label(session.displayName, systemImage: "apple.terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    /// The output line that matched, if the match was in the output.
    private var snippet: String? {
        guard !entry.command.localizedStandardContains(query) else { return nil }
        return entry.plainOutput
            .split(separator: "\n")
            .first { $0.localizedStandardContains(query) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
