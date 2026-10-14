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
