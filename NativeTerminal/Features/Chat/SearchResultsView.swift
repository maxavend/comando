import SwiftUI

struct SearchResultsView: View {
    let query: String
    let scope: SearchScope
    let onSelect: () -> Void

    @Environment(TerminalController.self) private var controller

    var body: some View {
        let results = controller.search(query, in: scope == .session ? controller.selectedSessionID : nil)
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { entry in
                    Button {
                        open(entry)
                    } label: {
                        SearchResultRow(entry: entry, query: query, showsSession: scope == .all)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Buscar")
        .navigationSubtitle(results.isEmpty ? "" : String(localized: "\(results.count) resultados"))
    }

    private func open(_ entry: CommandEntry) {
        guard let session = entry.session else { return }
        controller.selectedSessionID = session.id
        controller.focusedEntryID = entry.id
        onSelect()
    }
}

private struct SearchResultRow: View {
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
