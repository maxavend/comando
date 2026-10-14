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
                ContentUnavailableView.search
            } else {
                // A plain stack (not a List) keeps rows on the same inset as the chat.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { entry in
                            SearchResultRow(entry: entry, query: query, showsSession: scope == .all) {
                                open(entry)
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.contentInset)
                    .padding(.vertical, Metrics.transcriptVerticalInset)
                }
            }
        }
        .navigationTitle("Buscar")
        .navigationSubtitle(results.isEmpty ? Text("") : Text("^[\(results.count) resultado](inflect: true)"))
    }

    private func open(_ entry: CommandEntry) {
        guard let session = entry.session else { return }
        controller.selectedSessionID = session.id
        controller.focusedEntryID = entry.id
        onSelect()
    }
}
