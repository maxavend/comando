import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The message field at the bottom of the chat.
///
/// When the shell is idle it sends commands; while a command runs it sends
/// lines to the program's input, and switches to a secure field when the
/// program turns echo off (password prompts).
struct ComposerView: View {
    @Binding var text: String
    let shell: ShellSession?
    let directory: String
    /// Commands of this session, oldest first.
    let history: [String]
    /// Extra trailing space matching an always-visible scroller in the transcript.
    var trailingInset: CGFloat = 0
    let onSubmit: (String) -> Void

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @Environment(TerminalController.self) private var controller
    @FocusState private var isFocused: Bool
    @State private var secret = ""
    @State private var historyIndex: Int?
    @State private var savedDraft = ""
    @State private var isImporting = false
    @State private var completions = CompletionProvider()
    @State private var candidates: [Completion] = []
    @State private var selection = 0
    /// The candidates panel opens only on Tab, so typing stays calm.
    @State private var isPanelOpen = false
    /// Running state as shown: lags `isRunning` by `Metrics.busyStateDelay`.
    @State private var showsBusy = false

    private var phase: ShellSession.Phase { shell?.phase ?? .notStarted }
    private var isRunning: Bool { phase == .running || phase == .interactive }
    private var isPasswordPrompt: Bool { phase == .running && (shell?.echoDisabled ?? false) }

    var body: some View {
        VStack(spacing: 0) {
            // A zero-height anchor: the panel grows upward from the composer's top
            // edge without changing the composer's height, so nothing moves while typing.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 0)
                .overlay(alignment: .bottom) {
                    if showsPanel {
                        CompletionPanel(candidates: candidates, selection: selection, onSelect: accept)
                            .padding(.horizontal, Metrics.composerControlSize + Metrics.composerSpacing)
                            .padding(.bottom, Metrics.composerSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.12), value: showsPanel)
            controls
        }
        .padding(.leading, Metrics.contentInset)
        .padding(.trailing, Metrics.contentInset + trailingInset)
        .padding(.vertical, Metrics.composerVerticalPadding)
        .onAppear { isFocused = true }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .idle { isFocused = true }
        }
        .task(id: isRunning) {
            guard isRunning else {
                showsBusy = false
                return
            }
            try? await Task.sleep(for: Metrics.busyStateDelay)
            guard !Task.isCancelled, isRunning else { return }
            withAnimation(.smooth(duration: 0.2)) { showsBusy = true }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { insert(urls) }
        }
    }

    private var controls: some View {
        // Spacing 0 keeps each glass shape separate, so the send button changing
        // color never ripples into the field next to it.
        GlassEffectContainer(spacing: 0) {
            HStack(alignment: .bottom, spacing: Metrics.composerSpacing) {
                actionsMenu
                field
                    .padding(.horizontal, Metrics.composerFieldHorizontalPadding)
                    .padding(.vertical, Metrics.bubbleVerticalPadding)
                    .frame(minHeight: Metrics.composerControlSize)
                    .glassEffect(.regular, in: .rect(cornerRadius: Metrics.composerControlSize / 2))
                if showsBusy {
                    Button("Detener", systemImage: "stop.fill", action: interrupt)
                        .buttonStyle(.glassCircle(.destructive))
                        .help("Interrumpir el comando (⌘.)")
                }
                Button("Enviar", systemImage: "arrow.up", action: submit)
                    .buttonStyle(.glassCircle(.prominent))
                    .disabled(!canSubmit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Enviar (↩)")
            }
        }
    }

    // MARK: - Field

    @ViewBuilder
    private var field: some View {
        if isPasswordPrompt {
            HStack(spacing: Metrics.composerSpacing) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SecureField("Contraseña", text: $secret)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(submitSecret)
            }
            .font(.system(size: fontSize))
            .onAppear { isFocused = true }
        } else {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .lineLimit(1...8)
                .background(alignment: .topLeading) { ghost }
                .focused($isFocused)
                .disabled(phase == .interactive)
                .onSubmit(submit)
                .onKeyPress(.upArrow) { moveUp() }
                .onKeyPress(.downArrow) { moveDown() }
                .onKeyPress(keys: [.tab], phases: .down) { press in
                    press.modifiers.contains(.shift) ? moveUp() : completeWithTab()
                }
                .onKeyPress(.return) { acceptSelection() }
                .onKeyPress(.escape) { dismissPanel() }
                .onKeyPress(characters: ["c"], phases: .down) { press in
                    guard press.modifiers == .control, isRunning else { return .ignored }
                    shell?.interrupt()
                    return .handled
                }
                .onChange(of: text, initial: true) {
                    if historyIndex != nil, text != currentHistoryText { historyIndex = nil }
                    updateCandidates()
                }
                .onChange(of: directory) { updateCandidates() }
                .dropDestination(for: URL.self) { urls, _ in
                    insert(urls)
                }
                .accessibilityLabel("Comando")
                #if DEBUG
                .onDebugAction("#tab") { _ in _ = completeWithTab() }
                #endif
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Recetas…", systemImage: "wand.and.sparkles") {
                controller.isShowingRecipes = true
            }
            Divider()
            Button("Insertar ruta de archivo…", systemImage: "doc.badge.plus") {
                isImporting = true
            }
            Button("Insertar carpeta actual", systemImage: "folder") {
                text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + ShellEscape.path(URL(filePath: directory))
            }
            Divider()
            Button("Detener comando", systemImage: "stop") { shell?.interrupt() }
                .disabled(!isRunning)
            Button("Enviar fin de entrada (EOF)", systemImage: "eject") { shell?.sendEOF() }
                .disabled(!isRunning)
            Button("Abrir como terminal", systemImage: "macwindow") { shell?.openInTerminal() }
                .disabled(phase != .running)
        } label: {
            Label("Acciones", systemImage: "plus")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glassCircle)
        .help("Acciones")
    }

    /// Just the program name, so the placeholder stays on one line.
    private var runningProgram: String {
        ShellSession.firstWord(of: shell?.live?.command ?? "")
    }

    private var placeholder: String {
        if isRunning && !showsBusy { return String(localized: "Escribe un comando") }
        return switch phase {
        case .running:
            String(localized: "Enviar entrada a \(runningProgram)")
        case .interactive:
            String(localized: "\(runningProgram) está usando la terminal")
        case .exited:
            String(localized: "El shell terminó · escribe para reiniciarlo")
        default:
            String(localized: "Escribe un comando")
        }
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        if isPasswordPrompt { return true }
        if phase == .interactive { return false }
        // Empty lines are valid input for a running program (e.g. “Press Enter”).
        return isRunning || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        if isPasswordPrompt {
            submitSecret()
            return
        }
        guard canSubmit else { return }
        let value = text
        text = ""
        historyIndex = nil
        onSubmit(value)
    }

    private func interrupt() {
        shell?.interrupt()
    }

    private func submitSecret() {
        shell?.sendLine(secret)
        secret = ""
    }

    private func insert(_ urls: [URL]) {
        let paths = urls.map(ShellEscape.path).joined(separator: " ")
        guard !paths.isEmpty else { return }
        if !text.isEmpty && !text.hasSuffix(" ") { text += " " }
        text += paths
        isFocused = true
    }

    // MARK: - History

    private var currentHistoryText: String? {
        historyIndex.map { history[$0] }
    }

    private func browseHistory(by offset: Int) -> KeyPress.Result {
        // Only take over the arrows on a single line, when not editing a draft.
        guard !history.isEmpty, !text.contains("\n") else { return .ignored }
        guard text.isEmpty || historyIndex != nil else { return .ignored }
        if historyIndex == nil {
            guard offset < 0 else { return .ignored }
            savedDraft = text
            historyIndex = history.count
        }
        let next = (historyIndex ?? history.count) + offset
        if next >= history.count {
            historyIndex = nil
            text = savedDraft
        } else {
            historyIndex = max(0, next)
            text = history[max(0, next)]
        }
        return .handled
    }

    // MARK: - Completion

    /// The rest of the suggested completion, drawn in gray after the typed text.
    private var ghost: some View {
        Text("\(Text(text).foregroundStyle(.clear))\(Text(ghostRemainder).foregroundStyle(.tertiary))")
            .font(.system(size: fontSize))
            .lineLimit(1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var ghostRemainder: String {
        guard isFocused, !text.contains("\n"), candidates.indices.contains(selection) else { return "" }
        let candidate = candidates[selection]
        // A single typed letter matches too much; wait for a second one,
        // unless it's something the user ran before.
        guard isPanelOpen || text.count >= 2 || candidate.kind == .history else { return "" }
        guard candidate.completion.hasPrefix(text) else { return "" }
        return String(candidate.completion.dropFirst(text.count))
    }

    private var showsPanel: Bool {
        isPanelOpen && isFocused && !isRunning && candidates.count > 1
    }

    private func updateCandidates() {
        selection = 0
        isPanelOpen = false
        guard !isRunning, historyIndex == nil, !text.isEmpty else {
            candidates = []
            return
        }
        candidates = completions.suggestions(
            for: text,
            directory: directory,
            pathEntries: shell?.pathEntries ?? [],
            history: history,
            limit: 6
        )
    }

    private func accept(_ candidate: Completion) {
        text = candidate.completion
        isFocused = true
    }

    /// Tab completes like a shell: the only match, then the shared beginning,
    /// then a panel to choose from; with the panel open it moves to the next one.
    private func completeWithTab() -> KeyPress.Result {
        guard !isRunning else { return .ignored }
        if showsPanel {
            selection = (selection + 1) % candidates.count
            return .handled
        }
        switch candidates.count {
        case 0:
            if let completed = completions.tabCompletion(for: text, directory: directory, pathEntries: shell?.pathEntries ?? []) {
                text = completed
            }
        case 1:
            accept(candidates[0])
        default:
            let shared = candidates.dropFirst().reduce(candidates[0].completion) { String($0.commonPrefix(with: $1.completion)) }
            if shared.count > text.count && candidates.allSatisfy({ $0.completion.hasPrefix(text) }) {
                text = shared
            } else {
                isPanelOpen = true
            }
        }
        return .handled
    }

    private func acceptSelection() -> KeyPress.Result {
        guard showsPanel, candidates.indices.contains(selection) else { return .ignored }
        accept(candidates[selection])
        return .handled
    }

    private func moveUp() -> KeyPress.Result {
        guard showsPanel else { return browseHistory(by: -1) }
        selection = (selection - 1 + candidates.count) % candidates.count
        return .handled
    }

    private func moveDown() -> KeyPress.Result {
        guard showsPanel else { return browseHistory(by: 1) }
        selection = (selection + 1) % candidates.count
        return .handled
    }

    private func dismissPanel() -> KeyPress.Result {
        guard showsPanel else { return .ignored }
        isPanelOpen = false
        return .handled
    }
}
