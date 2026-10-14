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
    @FocusState private var isFocused: Bool
    @State private var secret = ""
    @State private var historyIndex: Int?
    @State private var savedDraft = ""
    @State private var isImporting = false
    @State private var completions = CompletionProvider()

    private var phase: ShellSession.Phase { shell?.phase ?? .notStarted }
    private var isRunning: Bool { phase == .running || phase == .interactive }
    private var isPasswordPrompt: Bool { phase == .running && (shell?.echoDisabled ?? false) }

    var body: some View {
        GlassEffectContainer(spacing: Metrics.composerSpacing) {
            HStack(alignment: .bottom, spacing: Metrics.composerSpacing) {
                actionsMenu
                field
                    .padding(.horizontal, Metrics.composerFieldHorizontalPadding)
                    .padding(.vertical, Metrics.bubbleVerticalPadding)
                    .frame(minHeight: Metrics.composerControlSize)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.composerControlSize / 2))
                if isRunning {
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
        .padding(.leading, Metrics.contentInset)
        .padding(.trailing, Metrics.contentInset + trailingInset)
        .padding(.vertical, Metrics.composerVerticalPadding)
        .onAppear { isFocused = true }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .idle { isFocused = true }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { insert(urls) }
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
            .font(.system(size: fontSize, design: .monospaced))
            .onAppear { isFocused = true }
        } else {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize, design: .monospaced))
                .lineLimit(1...8)
                .focused($isFocused)
                .disabled(phase == .interactive)
                .onSubmit(submit)
                .textInputSuggestions(suggestions) { completion in
                    Label(completion.title, systemImage: completion.systemImage)
                        .textInputCompletion(completion.completion)
                }
                .onKeyPress(.upArrow) { browseHistory(by: -1) }
                .onKeyPress(.downArrow) { browseHistory(by: 1) }
                .onKeyPress(.tab) { completeWithTab() }
                .onKeyPress(characters: ["c"], phases: .down) { press in
                    guard press.modifiers == .control, isRunning else { return .ignored }
                    shell?.interrupt()
                    return .handled
                }
                .onChange(of: text) {
                    if historyIndex != nil, text != currentHistoryText { historyIndex = nil }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    insert(urls)
                }
                .accessibilityLabel("Comando")
        }
    }

    private var actionsMenu: some View {
        Menu {
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

    private var placeholder: String {
        switch phase {
        case .running:
            String(localized: "Enviar entrada a \(shell?.live?.command ?? "")")
        case .interactive:
            String(localized: "\(shell?.live?.command ?? "") está usando la terminal")
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
        guard !history.isEmpty, !text.contains("\n"), suggestions.isEmpty || historyIndex != nil else { return .ignored }
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

    private var suggestions: [Completion] {
        guard !isRunning, historyIndex == nil else { return [] }
        return completions.suggestions(
            for: text,
            directory: directory,
            pathEntries: shell?.pathEntries ?? [],
            history: history
        )
    }

    private func completeWithTab() -> KeyPress.Result {
        guard !isRunning else { return .ignored }
        if let completed = completions.tabCompletion(for: text, directory: directory, pathEntries: shell?.pathEntries ?? []) {
            text = completed
        }
        return .handled
    }
}
