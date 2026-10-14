import AppKit
import SwiftData
import SwiftUI

struct ChatView: View {
    let session: TerminalSession

    @Environment(TerminalController.self) private var controller
    @Query private var entries: [CommandEntry]
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var draft = ""
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isConfirmingDelete = false
    @State private var highlightedEntryID: UUID?
    @State private var lastWidth: CGFloat = 800
    /// Width of the transcript content; less than the view when a scroller takes space.
    @State private var contentWidth: CGFloat = 800
    @State private var position = ScrollPosition(edge: .bottom)
    /// Whether the transcript follows new output. Only the user's own
    /// scrolling changes it; resizes and new output keep the last state.
    @State private var isPinnedToBottom = true
    @State private var isAtBottom = true

    init(session: TerminalSession) {
        self.session = session
        let id = session.id
        _entries = Query(
            filter: #Predicate<CommandEntry> { $0.session?.id == id },
            sort: \.startedAt
        )
    }

    var body: some View {
        let shell = controller.shells[session.id]
        let directory = shell?.directory ?? session.directory

        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                    EntryView(
                        entry: entry,
                        previous: index > 0 ? entries[index - 1] : nil,
                        shell: shell,
                        isHighlighted: highlightedEntryID == entry.id,
                        onEdit: { draft = $0 }
                    )
                    .id(entry.id)
                }
            }
            .padding(.horizontal, Metrics.contentInset)
            .padding(.top, Metrics.transcriptVerticalInset - Metrics.exchangeSpacing)
            .padding(.bottom, Metrics.transcriptVerticalInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                contentWidth = width
                updateColumns()
            }
        }
        .overlay {
            if entries.isEmpty {
                EmptyChatView(directory: directory)
            }
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - Metrics.exchangeSpacing
        } action: { _, atBottom in
            isAtBottom = atBottom
        }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
            followOutput()
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            // Only scrolling the user did decides whether to keep following.
            if newPhase == .idle, [.tracking, .interacting, .decelerating].contains(oldPhase) {
                isPinnedToBottom = isAtBottom
            }
        }
        .onChange(of: entries.last?.id) {
            isPinnedToBottom = true
            withAnimation(.smooth) { position.scrollTo(edge: .bottom) }
        }
        .task(id: controller.focusedEntryID) {
            await reveal(controller.focusedEntryID)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            lastWidth = size.width
            followOutput()
        }
        .onChange(of: fontSize) {
            updateColumns()
        }
        .safeAreaBar(edge: .bottom) {
            ComposerView(
                text: $draft,
                shell: shell,
                directory: directory,
                history: entries.map(\.command),
                trailingInset: max(0, lastWidth - contentWidth),
                onSubmit: { controller.submit($0, in: session) }
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            insertPaths(urls)
        }
        #if DEBUG
        .onDebugAction("#type") { draft = $0 }
        .onDebugAction("#rename") { _ in
            newName = session.customName ?? ""
            isRenaming = true
        }
        .onDebugAction("#delete") { _ in isConfirmingDelete = true }
        #endif
        .navigationTitle(session.displayName)
        .navigationSubtitle(subtitle(for: directory))
        .toolbar { toolbar(directory: directory) }
        .task(id: session.id) {
            controller.shell(for: session)
            updateColumns()
        }
        .alert("Renombrar sesión", isPresented: $isRenaming) {
            TextField("Nombre", text: $newName)
            Button("Renombrar") { controller.rename(session, to: newName) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Déjalo vacío para usar el nombre de la carpeta.")
        }
        .confirmationDialog("¿Eliminar esta sesión?", isPresented: $isConfirmingDelete) {
            Button("Eliminar sesión", role: .destructive) { controller.delete(session) }
        } message: {
            Text("Se cerrará su shell y se borrará su historial. Esta acción no se puede deshacer.")
        }
    }

    @ToolbarContentBuilder
    private func toolbar(directory: String) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Mostrar en Finder", systemImage: "folder") {
                NSWorkspace.shared.open(URL(filePath: directory, directoryHint: .isDirectory))
            }
            .help("Mostrar la carpeta actual en Finder")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu("Más", systemImage: "ellipsis") {
                Button("Renombrar…", systemImage: "pencil") {
                    newName = session.customName ?? ""
                    isRenaming = true
                }
                Button("Reiniciar shell", systemImage: "arrow.clockwise") {
                    controller.restartShell(of: session)
                }
                Divider()
                Button("Limpiar historial", systemImage: "clear") {
                    controller.clearHistory(of: session)
                }
                Button("Eliminar sesión…", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
            .help("Más acciones")
        }
    }

    /// The folder path, unless the title already says it (e.g. “~”).
    private func subtitle(for directory: String) -> String {
        let path = ShellEscape.abbreviate(directory)
        return path == session.displayName ? "" : path
    }

    // MARK: - Layout

    private func updateColumns() {
        controller.shells[session.id]?.setChatSize(columns: columns(forWidth: contentWidth), rows: 40)
    }

    /// Columns that fit in an output bubble, so tools like `ls` lay out to the bubble width.
    /// `width` is the transcript content width, including its horizontal insets.
    private func columns(forWidth width: CGFloat) -> Int {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let characterWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let textWidth = width - Metrics.contentInset * 2 - Metrics.bubbleOppositeInset - Metrics.bubbleHorizontalPadding * 2
        return max(20, Int(textWidth / max(characterWidth, 1)))
    }

    private func insertPaths(_ urls: [URL]) {
        let paths = urls.map(ShellEscape.path).joined(separator: " ")
        guard !paths.isEmpty else { return }
        if !draft.isEmpty && !draft.hasSuffix(" ") { draft += " " }
        draft += paths
    }

    /// Keeps the newest output in view while the transcript is pinned to the bottom.
    private func followOutput() {
        guard isPinnedToBottom else { return }
        position.scrollTo(edge: .bottom)
    }

    private func reveal(_ entryID: UUID?) async {
        guard let entryID else { return }
        // Give the lazy stack a moment to lay out after switching sessions.
        try? await Task.sleep(for: .milliseconds(150))
        isPinnedToBottom = false
        withAnimation(.smooth) { position.scrollTo(id: entryID, anchor: .center) }
        highlightedEntryID = entryID
        controller.focusedEntryID = nil
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.smooth) { highlightedEntryID = nil }
    }
}
