import AppKit
import SwiftData
import SwiftUI

enum SearchScope: Hashable {
    case session
    case all
}

struct RootView: View {
    @Environment(TerminalController.self) private var controller
    @Query(sort: \TerminalSession.lastActivity, order: .reverse) private var sessions: [TerminalSession]
    @State private var searchText = ""
    @State private var searchScope = SearchScope.session

    var body: some View {
        let selectedID = controller.selectedSessionID
        let selected = sessions.first { $0.id == selectedID }

        NavigationSplitView {
            SessionListView(sessions: sessions)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 360)
        } detail: {
            if !searchText.isEmpty {
                SearchResultsView(query: searchText, scope: searchScope) {
                    searchText = ""
                }
            } else if let selected {
                ChatView(session: selected)
                    .id(selected.id)
            } else {
                ContentUnavailableView(
                    "Sin sesión",
                    systemImage: "apple.terminal",
                    description: Text("Crea una sesión nueva para empezar.")
                )
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Buscar comandos y salidas"))
        .searchScopes($searchScope) {
            Text("Esta sesión").tag(SearchScope.session)
            Text("Todas").tag(SearchScope.all)
        }
        .frame(minWidth: 680, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.markSelectedAsRead()
        }
    }
}
