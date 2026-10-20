import SwiftUI

struct SessionListView: View {
    let sessions: [TerminalSession]
    /// While searching, only the sessions that match stay in the list.
    @Binding var searchText: String
    @Binding var searchSelection: Int
    let onSearchSubmit: () -> Void

    @Environment(TerminalController.self) private var controller
    @State private var renaming: TerminalSession?
    @State private var newName = ""
    @State private var deleting: TerminalSession?
    @State private var customizing: TerminalSession?
    /// Sessions with a command or output that matches the search.
    @State private var matchingIDs: Set<UUID> = []

    var body: some View {
        @Bindable var controller = controller
        let shells = controller.shells

        let shown = sessions.filter(matches)
        let pinned = shown.filter(\.isPinned)
        let others = shown.filter { !$0.isPinned }

        List(selection: $controller.selectedSessionID) {
            if pinned.isEmpty {
                rows(others, shells: shells)
            } else {
                Section("Fijadas") {
                    rows(pinned, shells: shells)
                }
                Section("Sesiones") {
                    rows(others, shells: shells)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if shown.isEmpty, !searchText.isEmpty {
                Text("Ninguna sesión coincide")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // At the top of the sidebar, like Messages; the scope is chosen above the results.
        .safeAreaBar(edge: .top) {
            SidebarSearchField(text: $searchText, selection: $searchSelection, onSubmit: onSearchSubmit)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .task(id: searchText) {
            matchingIDs = Set(controller.search(searchText, in: nil).compactMap { $0.session?.id })
        }
        .toolbar {
            ToolbarItem {
                Button("Nueva sesión", systemImage: "square.and.pencil") {
                    controller.createSession()
                }
                .help("Nueva sesión (⌘T)")
            }
        }
        .alert("Renombrar sesión", item: $renaming) { session in
            TextField("Nombre", text: $newName)
            Button("Renombrar") {
                controller.rename(session, to: newName)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Déjalo vacío para usar el nombre de la carpeta.")
        }
        .sheet(item: $customizing) { session in
            SessionAppearanceEditor(session: session) { controller.save() }
        }
        .confirmationDialog("¿Eliminar esta sesión?", item: $deleting) { session in
            Button("Eliminar sesión", role: .destructive) {
                controller.delete(session)
            }
        } message: { _ in
            Text("Se cerrará su shell y se borrará su historial. Esta acción no se puede deshacer.")
        }
    }

    private func matches(_ session: TerminalSession) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return matchingIDs.contains(session.id)
            || session.displayName.localizedStandardContains(query)
            || FolderName.breadcrumb(session.directory).localizedStandardContains(query)
    }

    @ViewBuilder
    private func rows(_ sessions: [TerminalSession], shells: [UUID: ShellSession]) -> some View {
        ForEach(sessions) { session in
            SessionRow(session: session, shell: shells[session.id])
                .tag(session.id)
                .contextMenu {
                    contextMenu(for: session)
                }
        }
    }

    @ViewBuilder
    private func contextMenu(for session: TerminalSession) -> some View {
        if let shell = controller.shells[session.id], shell.isBusy {
            Button("Detener comando", systemImage: "stop.circle") { shell.interrupt() }
            if let url = shell.live?.localURL {
                Button("Abrir en el navegador", systemImage: "safari") { NSWorkspace.shared.open(url) }
            }
            Divider()
        }
        Button(session.isPinned ? "Dejar de fijar" : "Fijar arriba", systemImage: session.isPinned ? "pin.slash" : "pin") {
            session.isPinned.toggle()
            controller.save()
        }
        Button("Personalizar…", systemImage: "face.smiling") {
            customizing = session
        }
        Button("Renombrar…", systemImage: "pencil") {
            newName = session.customName ?? ""
            renaming = session
        }
        Button("Nueva sesión en esta carpeta", systemImage: "plus.square.on.square") {
            controller.createSession(directory: controller.shells[session.id]?.directory ?? session.directory)
        }
        Button("Mostrar en Finder", systemImage: "folder") {
            NSWorkspace.shared.open(URL(filePath: session.directory, directoryHint: .isDirectory))
        }
        Divider()
        Button("Limpiar historial", systemImage: "clear") {
            controller.clearHistory(of: session)
        }
        Button("Eliminar sesión…", systemImage: "trash", role: .destructive) {
            deleting = session
        }
    }
}
