import SwiftUI
import UniformTypeIdentifiers

struct SessionListView: View {
    let sessions: [TerminalSession]
    /// While searching, only the sessions that match stay in the list.
    @Binding var searchText: String
    @Binding var searchSelection: Int
    let onSearchSubmit: () -> Void

    @Environment(TerminalController.self) private var controller
    /// Sessions waiting for the delete confirmation.
    @State private var deleting: [TerminalSession] = []
    @State private var customizing: TerminalSession?
    /// Sessions with a command or output that matches the search.
    @State private var matchingIDs: Set<UUID> = []
    @AppStorage("showsArchivedSessions") private var showsArchived = false
    /// Folders the user added to the sidebar, one path per line.
    @AppStorage(SidebarFolders.key) private var storedFolders = ""
    /// Added folders the user folded, one path per line (kept between launches).
    @AppStorage("collapsedSessionGroups") private var collapsedGroups = ""
    /// The same, as view state: List animates rows in and out for a change
    /// of @State, not of UserDefaults.
    @State private var collapsed: Set<String> = []

    var body: some View {
        @Bindable var controller = controller
        let shells = controller.shells

        let shown = sessions.filter(matches)
        let active = shown.filter { !$0.isArchived }
        let pinned = active.filter(\.isPinned)
        let others = active.filter { !$0.isPinned }
        let archived = shown.filter(\.isArchived)
        let folders = SidebarFolders.list(storedFolders)
        let inFolder = Dictionary(grouping: others) { SidebarFolders.folder(for: $0, among: folders) ?? "" }
        let loose = inFolder[""] ?? []
        let isSearching = !searchText.isEmpty

        // The search field sits above the list, like in Messages: no bar
        // around it, so no line or shade under it on scroll or hover.
        VStack(spacing: 0) {
        SidebarSearchField(text: $searchText, selection: $searchSelection, onSubmit: onSearchSubmit)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        List(selection: selection) {
            if !pinned.isEmpty {
                Section {
                    rows(pinned, shells: shells)
                } header: {
                    SidebarHeading("Fijadas")
                        .padding(.bottom, Metrics.sidebarHeadingSpacing)
                }
            }
            // The folders the user added, each with its sessions, like
            // projects in a sidebar. While searching, only those with matches.
            if !isSearching || folders.contains(where: { !(inFolder[$0] ?? []).isEmpty }) {
                Section {
                    // An action row, like “Nuevo” at the top of a sidebar.
                    if !isSearching {
                        AddFolderRow { controller.isAddingSidebarFolder = true }
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                    }
                    ForEach(folders, id: \.self) { folder in
                        let items = inFolder[folder] ?? []
                        if !isSearching || !items.isEmpty {
                            let expanded = isExpanded(folder)
                            FolderRow(folder: folder, isExpanded: expanded,
                                      onNewSession: { controller.createSession(directory: folder) },
                                      onRemove: { storedFolders = SidebarFolders.removing(folder, from: storedFolders) })
                                .selectionDisabled()
                                .listRowSeparator(.hidden)
                            if expanded.wrappedValue {
                                rows(items, shells: shells)
                            }
                        }
                    }
                }
            }
            if !loose.isEmpty {
                Section {
                    rows(loose, shells: shells)
                } header: {
                    SidebarHeading("Sesiones")
                        .padding(.bottom, Metrics.sidebarHeadingSpacing)
                }
            }
            if !archived.isEmpty {
                // Open while searching, so a match in an archived session shows.
                Section(isExpanded: searchText.isEmpty ? $showsArchived : .constant(true)) {
                    rows(archived, shells: shells)
                } header: {
                    HStack {
                        SidebarHeading("Archivadas")
                        Spacer()
                        Text(archived.count, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, Metrics.sidebarHeadingSpacing)
                }
            }
        }
        .listStyle(.sidebar)
        // A folder dragged from Finder becomes one of the sidebar's folders.
        .dropDestination(for: URL.self) { urls, _ in
            let added = urls.filter(\.hasDirectoryPath)
            for url in added {
                storedFolders = SidebarFolders.adding(url.path(percentEncoded: false), to: storedFolders)
            }
            return !added.isEmpty
        }
        .fileImporter(isPresented: $controller.isAddingSidebarFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                storedFolders = SidebarFolders.adding(url.path(percentEncoded: false), to: storedFolders)
            }
        }
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
        .onAppear { collapsed = Set(SidebarFolders.list(collapsedGroups)) }
        .onChange(of: collapsedGroups) { _, stored in
            let folders = Set(SidebarFolders.list(stored))
            if folders != collapsed { collapsed = folders }
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

    private func isExpanded(_ folder: String) -> Binding<Bool> {
        Binding(
            get: { !searchText.isEmpty || !collapsed.contains(folder) },
            set: { expanded in
                if expanded { collapsed.remove(folder) } else { collapsed.insert(folder) }
                collapsedGroups = collapsed.sorted().joined(separator: "\n")
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
        // Name, symbol and color in one place.
        Button("Personalizar…", systemImage: "face.smiling") {
            customizing = session
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

/// One of the folders added to the sidebar: its name, a chevron next to it on
/// hover that folds or unfolds its sessions (as does a click on the name), and
/// + for a new session there.
private struct FolderRow: View {
    let folder: String
    @Binding var isExpanded: Bool
    let onNewSession: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.smooth(duration: 0.28)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    SidebarHeading(FolderName.display(folder))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(isHovering || !isExpanded ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(FolderName.breadcrumb(folder))
            .accessibilityLabel(FolderName.display(folder))
            .accessibilityValue(isExpanded ? Text("Desplegada") : Text("Plegada"))
            Spacer(minLength: 8)
            Button("Nueva sesión en \(FolderName.display(folder))", systemImage: "plus", action: onNewSession)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Nueva sesión en \(FolderName.display(folder))")
        }
        .padding(.vertical, 4)
        // A row starts 2 points further in than a section header: this lines
        // the folder's name up with “Sesiones”.
        .padding(.leading, -2)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Nueva sesión aquí", systemImage: "plus", action: onNewSession)
            Button("Mostrar en Finder", systemImage: "folder") {
                NSWorkspace.shared.open(URL(filePath: folder, directoryHint: .isDirectory))
            }
            Divider()
            Button("Quitar de la barra lateral", systemImage: "minus.circle", action: onRemove)
        }
    }
}

/// “Agregar carpeta”: a plus in a small circle and the label, like the
/// action rows at the top of a sidebar.
private struct AddFolderRow: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(.fill.secondary, in: .circle)
                Text("Agregar carpeta")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(.fill.quaternary.opacity(isHovering ? 1 : 0), in: .rect(cornerRadius: 8, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .onHover { isHovering = $0 }
        .help("Elige una carpeta, o arrástrala aquí desde Finder, para abrir terminales en ella con un clic.")
    }
}

/// The sidebar's headings — sections and added folders alike — in one style:
/// body text, semibold, secondary, instead of small header caps.
private struct SidebarHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .lineLimit(1)
    }
}
