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

    static let horizontalPadding: CGFloat = 20

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

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if entries.isEmpty {
                        EmptyChatView(directory: directory)
                    }
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
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 16)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onChange(of: entries.last?.id) { _, last in
                guard let last else { return }
                withAnimation(.smooth) { proxy.scrollTo(last, anchor: .bottom) }
            }
            .task(id: controller.focusedEntryID) {
                await reveal(controller.focusedEntryID, with: proxy)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            updateColumns(forWidth: width)
        }
        .onChange(of: fontSize) {
            controller.shells[session.id]?.setChatSize(columns: columns(forWidth: lastWidth), rows: 40)
        }
        .safeAreaBar(edge: .bottom) {
            ComposerView(
                text: $draft,
                shell: shell,
                directory: directory,
                history: entries.map(\.command),
                onSubmit: { controller.submit($0, in: session) }
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            insertPaths(urls)
        }
        .navigationTitle(session.displayName)
        .navigationSubtitle(ShellEscape.abbreviate(directory))
        .toolbar { toolbar(directory: directory) }
        .task(id: session.id) {
            controller.shell(for: session)
            updateColumns(forWidth: lastWidth)
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

    // MARK: - Layout

    private func updateColumns(forWidth width: CGFloat) {
        lastWidth = width
        controller.shells[session.id]?.setChatSize(columns: columns(forWidth: width), rows: 40)
    }

    /// Columns that fit in an output bubble, so tools like `ls` lay out to the bubble width.
    private func columns(forWidth width: CGFloat) -> Int {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let characterWidth = ("M" as NSString).size(withAttributes: [.font: font]).width
        let textWidth = width - Self.horizontalPadding * 2 - BubbleMetrics.trailingInset - BubbleMetrics.horizontalPadding * 2
        return max(20, Int(textWidth / max(characterWidth, 1)))
    }

    private func insertPaths(_ urls: [URL]) {
        let paths = urls.map(ShellEscape.path).joined(separator: " ")
        guard !paths.isEmpty else { return }
        if !draft.isEmpty && !draft.hasSuffix(" ") { draft += " " }
        draft += paths
    }

    private func reveal(_ entryID: UUID?, with proxy: ScrollViewProxy) async {
        guard let entryID else { return }
        // Give the lazy stack a moment to lay out after switching sessions.
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.smooth) { proxy.scrollTo(entryID, anchor: .center) }
        highlightedEntryID = entryID
        controller.focusedEntryID = nil
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.smooth) { highlightedEntryID = nil }
    }
}

private struct EmptyChatView: View {
    let directory: String

    var body: some View {
        ContentUnavailableView {
            Label("Sesión nueva", systemImage: "apple.terminal")
        } description: {
            Text("Escribe un comando abajo para empezar.\nEstás en \(ShellEscape.abbreviate(directory)).")
        }
        .padding(.top, 80)
    }
}
