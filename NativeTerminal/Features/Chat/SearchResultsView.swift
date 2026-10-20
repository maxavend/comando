import SwiftData
import SwiftUI

/// What the sidebar search found, in sections like the search in Messages.
/// ↑ ↓ move through the results from the search field and ↩ opens one.
struct SearchResultsView: View {
    let query: String
    let sessions: [TerminalSession]
    /// The highlighted result, moved with the arrow keys in the search field.
    @Binding var selection: Int
    /// Bumped by ↩ in the search field.
    let openRequest: Int
    /// Clears the search once a result is opened.
    let onFinish: () -> Void

    @Environment(TerminalController.self) private var controller
    @Query(sort: \SavedRecipe.order) private var saved: [SavedRecipe]
    @State private var expanded: Set<String> = []

    var body: some View {
        let results = SearchResults(
            query: query,
            sessions: sessions,
            entries: controller.search(query, in: nil),
            current: controller.selectedSessionID,
            recipes: savedRecipes + SearchResults.rankedRecipes(for: query)
        )
        let visible = results.sections.map { section in
            (section, expanded.contains(section.id) ? section.items : Array(section.items.prefix(SearchResults.preview)))
        }
        let flat = visible.flatMap(\.1)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(visible, id: \.0.id) { section, items in
                        sectionView(section, items: items, flat: flat)
                    }
                }
                .padding(.horizontal, Metrics.contentInset)
                .padding(.top, 8)
                .padding(.bottom, Metrics.transcriptVerticalInset)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: selection) { _, index in
                guard flat.indices.contains(index) else {
                    selection = max(flat.count - 1, 0)
                    return
                }
                withAnimation(.smooth(duration: 0.15)) { proxy.scrollTo(flat[index].id) }
            }
        }
        .onChange(of: query) { selection = 0 }
        .onChange(of: flat.count) { _, count in selection = min(selection, max(count - 1, 0)) }
        .onChange(of: openRequest) {
            if flat.indices.contains(selection) { open(flat[selection]) }
        }
        .navigationTitle("Buscar")
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    @ViewBuilder
    private func sectionView(_ section: SearchResults.Section, items: [SearchItem], flat: [SearchItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !section.title.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(section.title)
                        .font(.headline)
                    Spacer()
                    if section.items.count > SearchResults.preview {
                        let isExpanded = expanded.contains(section.id)
                        Button(isExpanded ? "Ver menos" : "Ver los \(section.items.count)") {
                            withAnimation(.smooth(duration: 0.2)) {
                                if isExpanded { expanded.remove(section.id) } else { expanded.insert(section.id) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                    }
                }
                .padding(.horizontal, 10)
            }
            VStack(spacing: 2) {
                ForEach(items) { item in
                    let index = flat.firstIndex { $0.id == item.id } ?? -1
                    SearchItemRow(item: item, query: query, isSelected: index == selection,
                                  onOpen: { open(item) }, onRepeat: { repeatCommand(item) })
                        .id(item.id)
                        .onHover { if $0 { selection = index } }
                }
            }
        }
    }

    // MARK: - Actions

    private func open(_ item: SearchItem) {
        switch item {
        case .session(let session):
            controller.selectedSessionID = session.id
        case .command(let entry), .output(let entry, _):
            guard let session = entry.session else { return }
            controller.selectedSessionID = session.id
            controller.focusedEntryID = entry.id
        case .folder(let path):
            // The open session moves there; a new one opens if it's busy.
            if let session = selectedSession, !(controller.shells[session.id]?.isBusy ?? false) {
                controller.navigate(to: path, in: session)
            } else {
                controller.createSession(directory: path)
            }
        case .recipe(let recipe):
            // Written in the composer, ready to adjust and send.
            ensureSession()
            controller.draftRequest = recipe.command(with: [:])
        case .ask(let request):
            controller.ask(request, attachments: [], in: ensureSession())
        }
        onFinish()
    }

    private func repeatCommand(_ item: SearchItem) {
        guard case .command(let entry) = item, let session = entry.session else { return }
        controller.selectedSessionID = session.id
        controller.submit(entry.command, in: session)
        onFinish()
    }

    /// The user's own recipes that match, for the folder of the open session.
    private var savedRecipes: [Recipe] {
        let directory = selectedSession.map { controller.shells[$0.id]?.directory ?? $0.directory } ?? NSHomeDirectory()
        return saved.map { $0.recipe(in: directory) }.filter { $0.matches(query) }
    }

    private var selectedSession: TerminalSession? {
        sessions.first { $0.id == controller.selectedSessionID }
    }

    @discardableResult
    private func ensureSession() -> TerminalSession {
        if let selectedSession { return selectedSession }
        return controller.createSession()
    }
}

/// One result: an icon, what matched (in bold) and where it is.
private struct SearchItemRow: View {
    let item: SearchItem
    let query: String
    let isSelected: Bool
    let onOpen: () -> Void
    let onRepeat: () -> Void

    @Environment(TerminalController.self) private var controller

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                title
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.fill.secondary)
            }
        }
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Abrir", onOpen)
    }

    // MARK: Parts

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .session(let session):
            avatar(for: session, size: 28)
        case .command(let entry), .output(let entry, _):
            if let session = entry.session {
                avatar(for: session, size: 28)
            }
        case .folder(let path):
            tile(FolderName.systemImage(path), tint: .blue)
        case .recipe(let recipe):
            if let tint = recipe.tint {
                RecipeTile(systemImage: recipe.systemImage, colorIndex: tint)
            } else {
                tile(recipe.systemImage, tint: .orange)
            }
        case .ask:
            IntelligenceGlyph()
                .frame(width: 28, height: 28)
        }
    }

    private func avatar(for session: TerminalSession, size: CGFloat) -> some View {
        SessionAvatar(isRunning: false, emoji: session.emoji, colorIndex: session.colorIndex,
                      size: size, symbol: session.avatarSymbol(for: session.directory))
    }

    private func tile(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint.gradient, in: .rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var title: some View {
        switch item {
        case .session(let session):
            Text(AttributedString(session.displayName, highlighting: query))
        case .command(let entry):
            HStack(spacing: 4) {
                if entry.kind == .assistant {
                    Image(systemName: "sparkle").foregroundStyle(.secondary)
                }
                Text(AttributedString(entry.command, highlighting: query))
                    .font(entry.kind == .assistant ? .body : .body.monospaced())
            }
        case .output(_, let line):
            Text(AttributedString(line, highlighting: query))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        case .folder(let path):
            Text(AttributedString(FolderName.display(path), highlighting: query))
        case .recipe(let recipe):
            Text(AttributedString(recipe.title, highlighting: query))
        case .ask(let request):
            Text("Preguntar a Comando: «\(request)»")
        }
    }

    private var subtitle: String? {
        switch item {
        case .session(let session):
            FolderName.breadcrumb(session.directory)
        case .command(let entry):
            entry.session.map { session in
                let folder = FolderName.display(entry.directory)
                return folder == session.displayName ? folder : "\(session.displayName) · \(folder)"
            }
        case .output(let entry, _):
            entry.session.map { "\(entry.command) · \($0.displayName)" }
        case .folder(let path):
            FolderName.breadcrumb(path)
        case .recipe(let recipe):
            recipe.detail
        case .ask:
            String(localized: "Te explica cómo hacerlo o lo prepara por ti")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch item {
        case .command(let entry):
            if isSelected, entry.kind == .command {
                HStack(spacing: 4) {
                    Button("Copiar", systemImage: "doc.on.doc") { Pasteboard.copy(entry.command) }
                        .help("Copiar el comando")
                    Button("Repetir", systemImage: "arrow.clockwise", action: onRepeat)
                        .help("Volver a ejecutarlo en su sesión")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            } else {
                status(of: entry)
            }
        case .output(let entry, _):
            date(entry.startedAt)
        case .session(let session):
            date(session.lastActivity)
        case .folder:
            Text("Ir").font(.subheadline).foregroundStyle(.secondary)
        case .recipe, .ask:
            if isSelected {
                Image(systemName: "return").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func status(of entry: CommandEntry) -> some View {
        HStack(spacing: 6) {
            if entry.kind == .command, entry.finishedAt != nil, !entry.succeeded, !entry.wasStopped {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .help("Terminó con error")
            }
            date(entry.startedAt)
        }
    }

    private func date(_ date: Date) -> some View {
        Text(SessionRow.timestamp(for: date))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
