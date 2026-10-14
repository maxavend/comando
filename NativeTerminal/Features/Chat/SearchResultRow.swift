import SwiftUI

struct SearchResultRow: View {
    let entry: CommandEntry
    let query: String
    let showsSession: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.command)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.startedAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let snippet {
                    Text(snippet)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if showsSession, let session = entry.session {
                    Label(session.displayName, systemImage: "apple.terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Metrics.bubbleVerticalPadding + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .background {
                // The hover highlight extends past the text so the text stays on the inset.
                RoundedRectangle(cornerRadius: Metrics.bubbleCornerRadius / 2)
                    .fill(.fill.tertiary)
                    .padding(.horizontal, -Metrics.bubbleHorizontalPadding / 2)
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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
