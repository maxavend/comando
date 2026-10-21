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
    /// Files dropped on the chat, sent with the next request to the assistant.
    @Binding var attachments: [URL]
    let onSubmit: (String) -> Void
    let onAsk: (String, [URL]) -> Void
    /// An open conversation with an AI agent: messages go to it.
    var agent: AgentChat?
    var onAgent: (String) -> Void = { _ in }

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
    @State private var knownCommands: Set<String> = []
    @AppStorage(AppSettings.assistantEnabledKey) private var assistantEnabled = true

    private var phase: ShellSession.Phase { shell?.phase ?? .notStarted }
    private var isRunning: Bool { phase == .running || phase == .interactive }
    /// An AI agent has the terminal: the field writes to it.
    private var talksToAgent: Bool {
        phase == .interactive && AICommandLine.isAgent(shell?.live?.command ?? "")
    }
    /// Apple Intelligence will answer: what's typed goes to the assistant,
    /// or it's answering now. Agent CLIs don't light up the field.
    private var showsIntelligence: Bool { isAskingAssistant || isIntelligenceWorking }

    private var isIntelligenceWorking: Bool {
        controller.assistantRequestsInFlight > 0 && agent == nil && !isRunning
    }

    /// Writing to an agent in chat mode, with the shell free.
    private var chatsWithAgent: Bool { agent != nil && !isRunning }
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
        // Close to the window's edges, like Messages: the field spans the
        // whole bottom instead of floating in the middle.
        .padding(.horizontal, Metrics.composerEdgeInset)
        .padding(.top, Metrics.composerVerticalPadding)
        .padding(.bottom, Metrics.composerEdgeInset)
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
        glassControls
            // Words for an AI light up the field's edge, with ✨ on the send
            // button; while it answers, the light runs faster. Drawn above the
            // glass, so its rim and tint don't dull the colors.
            .overlayPreferenceValue(FieldBoundsKey.self) { anchor in
                GeometryReader { proxy in
                    if let anchor {
                        let rect = proxy[anchor]
                        IntelligenceGlow(shape: RoundedRectangle(cornerRadius: Metrics.composerControlSize / 2),
                                         isActive: showsIntelligence, isWorking: isIntelligenceWorking)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
    }

    private var glassControls: some View {
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
                    .anchorPreference(key: FieldBoundsKey.self, value: .bounds) { $0 }
                if let agent, agent.isResponding {
                    Button("Detener", systemImage: "stop.fill") { agent.stop() }
                        .buttonStyle(.glassCircle(.destructive))
                        .help("Detener la respuesta de \(agent.kind.rawValue)")
                } else if showsBusy {
                    Button("Detener", systemImage: "stop.fill", action: interrupt)
                        .buttonStyle(.glassCircle(.destructive))
                        .help("Interrumpir el comando (⌘.)")
                }
                // Always the plain send button: the field's edge light is what
                // says Apple Intelligence will answer.
                Button(action: submit) {
                    Label(showsIntelligence ? "Pedir al asistente" : "Enviar", systemImage: "arrow.up")
                }
                .buttonStyle(.glassCircle(.prominent))
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
                .help(isAskingAssistant ? "Pedir al asistente (↩)" : "Enviar (↩)")

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
            VStack(alignment: .leading, spacing: Metrics.statusSpacing + 2) {
                if !attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: Metrics.statusSpacing) {
                            ForEach(attachments, id: \.self) { url in
                                AttachmentChip(path: url.path(percentEncoded: false)) {
                                    attachments.removeAll { $0 == url }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                // The text never moves: the send button shows ✨ instead.
                textField
            }
            .task(id: shell?.pathEntries ?? []) {
                knownCommands = Set(ExecutableIndex.shared.names(for: shell?.pathEntries ?? []))
            }
        }
    }

    private var textField: some View {
        // The ghost sits behind the field as a sibling, not inside it: views
        // attached to this AppKit-backed field join its accessibility element,
        // and resolving its label then recursed until the app crashed.
        ZStack(alignment: .topLeading) {
            ghost
            inputField
        }
    }

    private var inputField: some View {
        // The title is the accessibility label.
        TextField("Comando", text: $text, prompt: Text(placeholder), axis: .vertical)
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(.system(size: fontSize))
            .lineLimit(1...8)
            .focused($isFocused)
            .disabled(phase == .interactive && !talksToAgent)
            .onSubmit(submit)
            // With the field empty, an AI agent's menus (“Do you trust this
            // folder?”) work from here too: the keys go to the agent.
            .onKeyPress(.upArrow) { forwardToAgent("\u{1B}[A") ?? moveUp() }
            .onKeyPress(.downArrow) { forwardToAgent("\u{1B}[B") ?? moveDown() }
            .onKeyPress(keys: [.tab], phases: .down) { press in
                if !press.modifiers.contains(.shift), let handled = forwardToAgent("\t") { return handled }
                return press.modifiers.contains(.shift) ? moveUp() : completeWithTab()
            }
            .onKeyPress(.return) { forwardToAgent("\r") ?? acceptSelection() }
            .onKeyPress(.escape) { forwardToAgent("\u{1B}") ?? dismissPanel() }
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
            .accessibilityIdentifier("composer")
            #if DEBUG
            .onDebugAction("#tab") { _ in _ = completeWithTab() }
            .onDebugAction("#submit") { _ in submit() }
            #endif
    }

    private var actionsMenu: some View {
        // Only what has no other place: recipes, stopping and the rest live
        // in the toolbar, the red button and the menu bar.
        Menu {
            Button("Insertar ruta de archivo…", systemImage: "doc.badge.plus") {
                isImporting = true
            }
            Button("Insertar carpeta actual", systemImage: "folder") {
                text += (text.isEmpty || text.hasSuffix(" ") ? "" : " ") + ShellEscape.path(URL(filePath: directory))
            }
        } label: {
            Label("Acciones", systemImage: "plus")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glassCircle)
        .help("Acciones")
    }

    /// Sends a key to the AI agent when the field is empty; nil otherwise, so
    /// the key does its usual job.
    private func forwardToAgent(_ key: String) -> KeyPress.Result? {
        guard talksToAgent, text.isEmpty else { return nil }
        shell?.sendRaw(Array(key.utf8))
        return .handled
    }

    /// Just the program name, so the placeholder stays on one line.
    private var runningProgram: String {
        ShellSession.firstWord(of: shell?.live?.command ?? "")
    }

    private var placeholder: String {
        if let agent, !isRunning { return String(localized: "Escríbele a \(agent.kind.displayName)") }
        if isRunning && !showsBusy { return String(localized: "Escribe un comando") }
        return switch phase {
        case .running:
            String(localized: "Enviar entrada a \(runningProgram)")
        case .interactive:
            talksToAgent
                ? String(localized: "Escríbele a \(runningProgram)")
                : String(localized: "\(runningProgram) está usando la terminal")
        case .exited:
            String(localized: "El shell terminó · escribe para reiniciarlo")
        default:
            assistantEnabled && AssistantEngine.isAvailable
                ? String(localized: "Escribe un comando o pide algo con tus palabras")
                : String(localized: "Escribe un comando")
        }
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        if isPasswordPrompt { return true }
        if phase == .interactive {
            return talksToAgent && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if chatsWithAgent {
            return agent?.isResponding == false && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        // Empty lines are valid input for a running program (e.g. “Press Enter”).
        return isRunning || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        if isPasswordPrompt {
            submitSecret()
            return
        }
        guard canSubmit else { return }
        if talksToAgent {
            shell?.sendMessage(text)
            text = ""
            return
        }
        if chatsWithAgent {
            onAgent(text)
            text = ""
            historyIndex = nil
            return
        }
        let value = text
        let asking = isAskingAssistant
        text = ""
        historyIndex = nil
        if asking {
            onAsk(value, attachments)
        } else if !attachments.isEmpty && !isRunning {
            // A real command with files attached: the files become its arguments.
            onSubmit(value + " " + attachments.map(ShellEscape.path).joined(separator: " "))
        } else {
            onSubmit(value)
        }
        attachments = []
    }

    /// Plain words (not a command) go to the assistant when it's available.
    private var isAskingAssistant: Bool {
        guard assistantEnabled, !isRunning, agent == nil, AssistantEngine.isAvailable else { return false }
        return IntentDetector.isPlainLanguage(text, knownCommands: knownCommands)
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

/// Where the message field is, so the AI light can be drawn above the glass.
private struct FieldBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
