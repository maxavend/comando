import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let session: TerminalSession

    @Environment(TerminalController.self) private var controller
    @Environment(\.openWindow) private var openWindow
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
    @State private var isDropTargeted = false
    @State private var gitInfo: GitInfo?
    @State private var attachments: [URL] = []
    /// Whether the transcript follows new output. Only the user's own
    /// scrolling changes it; resizes and new output keep the last state.
    @State private var isPinnedToBottom = true
    @State private var isAtBottom = true
    #if DEBUG
    @State private var savingRecipeFrom: CommandEntry?
    #endif

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

        presentations(of: transcript(shell: shell, directory: directory), directory: directory)
        // Floats over the title bar and the top of the chat, like the contact
        // in Messages; too tall to fit inside the toolbar.
        .overlay(alignment: .top) {
            // An open agent conversation counts as online, like a running program.
            VStack(spacing: Metrics.statusSpacing * 1.5) {
                SessionHeader(session: session, directory: directory,
                              isRunning: (shell?.isBusy ?? false) || controller.agentChats[session.id]?.isReady == true)
                // What's open, when its card is out of view: the green dot made visible.
                SessionActivityBar(session: session, shell: shell)
            }
            .animation(.smooth(duration: 0.25), value: controller.visibleActivityCards)
                .padding(.top, SessionHeader.topInset)
                .ignoresSafeArea(.container, edges: .top)
        }
        // A conversation open before quitting picks up again.
        .task(id: session.id) { _ = controller.agentChat(for: session) }
        .safeAreaBar(edge: .bottom) {
          VStack(spacing: Metrics.statusSpacing) {
            ComposerView(
                text: $draft,
                shell: shell,
                directory: directory,
                history: entries.map(\.command),
                attachments: $attachments,
                onSubmit: { controller.submit($0, in: session) },
                onAsk: { controller.ask($0, attachments: $1, in: session) },
                agent: controller.agentChats[session.id],
                onAgent: { controller.sendToAgent($0, in: session) }
            )
          }
          .animation(.smooth(duration: 0.25), value: controller.agentChats[session.id] != nil)
          .animation(.smooth(duration: 0.25), value: shell?.phase == .interactive)
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { isDropTargeted = $0 }
        .overlay(alignment: .top) {
            if isDropTargeted {
                DropHint()
                    .padding(.top, Metrics.contentInset)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }

    /// The scrolling list of exchanges, pinned to the newest output.
    private func transcript(shell: ShellSession?, directory: String) -> some View {
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
            // Clear of the floating header's name, which hangs below the bar.
            .padding(.top, Metrics.transcriptVerticalInset + SessionHeader.overhang)
            .padding(.bottom, Metrics.transcriptVerticalInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                contentWidth = width
                updateColumns()
            }
        }
        .overlay {
            if entries.isEmpty {
                EmptyChatView(
                    directory: directory,
                    onRun: { controller.submit($0, in: session) },
                    onPickFolder: { controller.isPickingFolder = true },
                    onShowRecipes: { controller.isShowingRecipes = true }
                )
            }
        }
        .scrollPosition($position)
        // Messages scroll under the header and the composer, fading softly
        // into their glass instead of stopping at a hard line.
        .scrollEdgeEffectStyle(.soft, for: .all)
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
            // Jump without animating: an animated scroll slides the new bubble
            // underneath the composer's glass, which reads as a flicker.
            isPinnedToBottom = true
            position.scrollTo(edge: .bottom)
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
    }

    /// Title, toolbar, alerts and sheets of the session.
    private func presentations(of content: some View, directory: String) -> some View {
        content
        .alert(
            controller.pendingCommand?.risk.title ?? "",
            isPresented: confirmingRisk,
            presenting: controller.pendingCommand
        ) { pending in
            if pending.trashAlternative != nil {
                Button("Mover a la Papelera") { controller.moveToTrashInstead() }
                    .keyboardShortcut(.defaultAction)
                Button("Eliminar para siempre", role: .destructive) { controller.confirmPendingCommand() }
            } else {
                Button("Ejecutar", role: .destructive) { controller.confirmPendingCommand() }
            }
            Button("Cancelar", role: .cancel) { draft = pending.command }
        } message: { pending in
            Text("\(pending.risk.explanation)\n\n\(pending.command)")
        }
        #if DEBUG
        .onDebugAction("#type") { draft = $0 }
        .onDebugAction("#attach") { attachments.append(URL(filePath: $0)) }
        .onDebugAction("#rename") { _ in
            newName = session.customName ?? ""
            isRenaming = true
        }
        .onDebugAction("#delete") { _ in isConfirmingDelete = true }
        .onDebugAction("#saverecipe") { _ in savingRecipeFrom = entries.last { $0.kind == .command } }
        .sheet(item: $savingRecipeFrom) { entry in
            SavedRecipeEditor(command: entry.command, directory: entry.directory)
        }
        #endif
        .navigationTitle(session.displayName)
        .navigationSubtitle(subtitle(for: directory))
        // A centered capsule names the session, like a conversation in
        // Messages; the window title stays for the Window menu and VoiceOver.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar { toolbar(directory: directory) }
        .task(id: session.id) {
            controller.shell(for: session)
            updateColumns()
        }
        // Refresh the branch and changes when the folder changes or a command ends.
        .task(id: "\(directory)|\(entries.last?.finishedAt?.timeIntervalSince1970 ?? 0)") {
            let info = await GitInfo.read(in: directory)
            if gitInfo != info { gitInfo = info }
        }
        .sheet(isPresented: showingRecipes) {
            RecipesView(
                directory: directory,
                onRun: { controller.submit($0, in: session) },
                onInsert: { draft = $0 }
            )
        }
        .onChange(of: controller.draftRequest) { _, request in
            guard let request, controller.selectedSessionID == session.id else { return }
            draft = request
            controller.draftRequest = nil
        }
        .fileImporter(isPresented: pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                controller.navigate(to: url.path(percentEncoded: false), in: session)
            }
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
        // Leading: where the session is (its folder and branch). Middle: kept
        // free for the floating session header. Trailing: what to do.
        ToolbarItem(placement: .navigation) {
            FolderMenu(session: session, directory: directory)
        }
        if let gitInfo {
            ToolbarItem(placement: .navigation) {
                GitMenu(info: gitInfo, isBusy: controller.shells[session.id]?.isBusy ?? false) {
                    controller.submit($0, in: session)
                }
            }
        }

        ToolbarItem(placement: .principal) {
            Color.clear.frame(width: 160, height: 1)
                .accessibilityHidden(true)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .primaryAction) {
            Button("Recetas", systemImage: "wand.and.sparkles") {
                controller.isShowingRecipes = true
            }
            .help("Buscar qué hacer (⌘K)")
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
                Button("Herramientas instaladas…", systemImage: "shippingbox") {
                    openWindow(id: "tools")
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

    /// Where the session is, as Finder names it (“Inicio › Documentos”),
    /// unless the title already says it all.
    private func subtitle(for directory: String) -> String {
        let breadcrumb = FolderName.breadcrumb(directory)
        return breadcrumb == session.displayName ? "" : breadcrumb
    }

    private var showingRecipes: Binding<Bool> {
        Binding(
            get: { controller.isShowingRecipes && controller.selectedSessionID == session.id },
            set: { controller.isShowingRecipes = $0 }
        )
    }

    private var pickingFolder: Binding<Bool> {
        Binding(
            get: { controller.isPickingFolder && controller.selectedSessionID == session.id },
            set: { controller.isPickingFolder = $0 }
        )
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

    /// A single folder dropped on the chat opens it; anything else is typed
    /// into the composer as paths.
    @discardableResult
    private func handleDrop(_ urls: [URL]) -> Bool {
        if urls.count == 1, let url = urls.first, url.hasDirectoryPath || isFolder(url),
           !(controller.shells[session.id]?.isBusy ?? false) {
            controller.navigate(to: url.path(percentEncoded: false), in: session)
            return true
        }
        // Files become attachments: ask the assistant what to do with them,
        // or type a command and they're added as its arguments.
        for url in urls where !attachments.contains(url) {
            attachments.append(url)
        }
        return true
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && url.pathExtension != "app"
    }

    private var confirmingRisk: Binding<Bool> {
        Binding(
            get: { controller.pendingCommand?.sessionID == session.id },
            set: { if !$0 { controller.pendingCommand = nil } }
        )
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
