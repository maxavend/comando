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
    /// Sessions waiting for the delete confirmation.
    @State private var deleting: [TerminalSession] = []
    @State private var customizing: TerminalSession?
    /// Sessions with a command or output that matches the search.
    @State private var matchingIDs: Set<UUID> = []
    @AppStorage("showsArchivedSessions") private var showsArchived = false
    @AppStorage(SessionGrouping.key) private var grouping = SessionGrouping.date
    /// Folder groups the user folded, one path per line.
    @AppStorage("collapsedSessionGroups") private var collapsedGroups = ""

    var body: some View {
        let shells = controller.shells

        let shown = sessions.filter(matches)
        let active = shown.filter { !$0.isArchived }
        let pinned = active.filter(\.isPinned)
        let others = active.filter { !$0.isPinned }
        let archived = shown.filter(\.isArchived)

        // The search field sits above the list, like in Messages: no bar
        // around it, so no line or shade under it on scroll or hover.
        VStack(spacing: 0) {
        SidebarSearchField(text: $searchText, selection: $searchSelection, onSubmit: onSearchSubmit)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        List(selection: selection) {
            if !pinned.isEmpty {
                Section("Fijadas") {
                    rows(pinned, shells: shells)
                }
            }
            if grouping == .folder {
                // Most recently used folder first, like the sessions inside it.
                ForEach(folderGroups(others), id: \.folder) { group in
                    let expanded = isExpanded(group.folder)
                    Section {
                        if expanded.wrappedValue {
                            rows(group.sessions, shells: shells)
                        }
                    } header: {
                        FolderGroupHeader(folder: group.folder, isExpanded: expanded) {
                            controller.createSession(directory: group.folder)
                        }
                    }
                }
            } else if pinned.isEmpty {
                rows(others, shells: shells)
            } else {
                Section("Sesiones") {
                    rows(others, shells: shells)
                }
            }
            if !archived.isEmpty {
                // Open while searching, so a match in an archived session shows.
                Section(isExpanded: searchText.isEmpty ? $showsArchived : .constant(true)) {
                    rows(archived, shells: shells)
                } header: {
                    HStack {
                        Text("Archivadas")
                        Spacer()
                        Text(archived.count, format: .number)
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: chosen(ids))
        }
        .onDeleteCommand { deleting = chosen(controller.selectedSessionIDs) }
        .overlay {
            if shown.isEmpty, !searchText.isEmpty {
                Text("Ninguna sesión coincide")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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
        .sessionDeleteConfirmation($deleting)
        }
    }

    /// The sidebar selection: one session opens its chat, several show what
    /// can be done with all of them.
    private var selection: Binding<Set<UUID>> {
        Binding(
            get: { controller.selectedSessionIDs },
            set: { controller.selectInSidebar($0) }
        )
    }

    // MARK: - Folder groups

    private func folderGroups(_ sessions: [TerminalSession]) -> [(folder: String, sessions: [TerminalSession])] {
        var order: [String] = []
        var members: [String: [TerminalSession]] = [:]
        for session in sessions {
            let folder = SessionGroup.folder(for: session)
            if members[folder] == nil { order.append(folder) }
            members[folder, default: []].append(session)
        }
        return order.map { ($0, members[$0] ?? []) }
    }

    private func isExpanded(_ folder: String) -> Binding<Bool> {
        Binding(
            get: { !searchText.isEmpty || !collapsedGroups.split(separator: "\n").contains(Substring(folder)) },
            set: { expanded in
                var folders = collapsedGroups.split(separator: "\n").map(String.init).filter { $0 != folder }
                if !expanded { folders.append(folder) }
                collapsedGroups = folders.joined(separator: "\n")
            }
        )
    }

    private func chosen(_ ids: Set<UUID>) -> [TerminalSession] {
        sessions.filter { ids.contains($0.id) }
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
                // A line between rows, none under the last row of a list or a group.
                .listRowSeparator(session.id == sessions.last?.id ? .hidden : .visible)
                // Like Mail and Messages: swipe left to archive or delete.
                .swipeActions(edge: .trailing) {
                    Button("Eliminar", systemImage: "trash", role: .destructive) { deleting = [session] }
                    if session.isArchived {
                        Button("Desarchivar", systemImage: "tray.and.arrow.up") { controller.unarchive([session]) }
                    } else {
                        Button("Archivar", systemImage: "archivebox") { controller.archive([session]) }
                            .tint(.indigo)
                    }
                }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func menu(for sessions: [TerminalSession]) -> some View {
        if sessions.count == 1, let session = sessions.first {
            singleMenu(for: session)
        } else if !sessions.isEmpty {
            let archived = sessions.allSatisfy(\.isArchived)
            if archived {
                Button("Desarchivar \(sessions.count) sesiones", systemImage: "tray.and.arrow.up") {
                    controller.unarchive(sessions)
                }
            } else {
                Button("Archivar \(sessions.count) sesiones", systemImage: "archivebox") {
                    controller.archive(sessions)
                }
            }
            Divider()
            Button("Eliminar \(sessions.count) sesiones…", systemImage: "trash", role: .destructive) {
                deleting = sessions
            }
        }
    }

    @ViewBuilder
    private func singleMenu(for session: TerminalSession) -> some View {
        if let shell = controller.shells[session.id], shell.isBusy {
            Button("Detener comando", systemImage: "stop.circle") { shell.interrupt() }
            if let url = shell.live?.localURL {
                Button("Abrir en el navegador", systemImage: "safari") { NSWorkspace.shared.open(url) }
            }
            Divider()
        }
        if !session.isArchived {
            Button(session.isPinned ? "Dejar de fijar" : "Fijar arriba", systemImage: session.isPinned ? "pin.slash" : "pin") {
                session.isPinned.toggle()
                controller.save()
            }
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
        if session.isArchived {
            Button("Desarchivar", systemImage: "tray.and.arrow.up") { controller.unarchive([session]) }
        } else {
            Button("Archivar", systemImage: "archivebox") { controller.archive([session]) }
        }
        Button("Limpiar historial", systemImage: "clear") {
            controller.clearHistory(of: session)
        }
        Button("Eliminar sesión…", systemImage: "trash", role: .destructive) {
            deleting = [session]
        }
    }
}

extension View {
    /// Asks before deleting one or more sessions; empty means no question.
    func sessionDeleteConfirmation(_ sessions: Binding<[TerminalSession]>) -> some View {
        modifier(SessionDeleteConfirmation(sessions: sessions))
    }
}

private struct SessionDeleteConfirmation: ViewModifier {
    @Binding var sessions: [TerminalSession]

    @Environment(TerminalController.self) private var controller

    func body(content: Content) -> some View {
        let count = sessions.count
        content.confirmationDialog(
            count == 1 ? "¿Eliminar esta sesión?" : "¿Eliminar \(count) sesiones?",
            isPresented: Binding(get: { !sessions.isEmpty }, set: { if !$0 { sessions = [] } })
        ) {
            Button(count == 1 ? "Eliminar sesión" : "Eliminar \(count) sesiones", role: .destructive) {
                controller.delete(sessions)
                sessions = []
            }
        } message: {
            Text(count == 1
                 ? "Se cerrará su shell y se borrará su historial. Esta acción no se puede deshacer."
                 : "Se cerrarán sus shells y se borrará su historial. Esta acción no se puede deshacer. Si solo quieres sacarlas de la lista, archívalas.")
        }
    }
}

/// A folder group's name in the sidebar, like a project in a sidebar: a
/// chevron next to the name on hover folds or unfolds it (as does a click on
/// the name), and + opens a new session there.
private struct FolderGroupHeader: View {
    let folder: String
    @Binding var isExpanded: Bool
    let onNewSession: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(FolderName.display(folder))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(isHovering || !isExpanded ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(FolderName.breadcrumb(folder))
            .accessibilityLabel(FolderName.display(folder))
            .accessibilityValue(isExpanded ? Text("Desplegado") : Text("Plegado"))
            .accessibilityHint(isExpanded ? Text("Pliega el grupo") : Text("Despliega el grupo"))
            Spacer()
            Button("Nueva sesión en \(FolderName.display(folder))", systemImage: "plus", action: onNewSession)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Nueva sesión en \(FolderName.display(folder))")
        }
        // Lines the + up with the times of the rows below, with room above
        // the first row (its selection mustn't touch the name).
        .padding(.trailing, 6)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .onHover { isHovering = $0 }
    }
}
