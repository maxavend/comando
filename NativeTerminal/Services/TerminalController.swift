import AppKit
import Foundation
import Observation
import SwiftData

/// App-wide owner of the running shells. Bridges shell events into the
/// SwiftData models that the views display.
@Observable
final class TerminalController {
    var selectedSessionID: UUID? {
        didSet {
            guard oldValue != selectedSessionID else { return }
            markSelectedAsRead()
        }
    }
    /// An entry the chat should scroll to (from search results).
    var focusedEntryID: UUID?
    /// Presents the folder picker of the selected session (“Ir a una carpeta…”).
    var isPickingFolder = false
    /// A risky command shown in a confirmation alert before it runs.
    var pendingCommand: PendingCommand?
    /// The assistant reply whose command waits for confirmation.
    @ObservationIgnored private var pendingProposalEntryID: UUID?
    /// Presents the welcome guide.
    var isShowingWelcome = false
    /// Presents the recipes finder (⌘K) for the selected session.
    var isShowingRecipes = false
    /// Text to place in the selected session's composer (from a recipe or hint).
    var draftRequest: String?
    /// Bumped when a command installs or removes tools, so lists reload.
    var installedToolsVersion = 0
    /// Requests the assistant is still answering; the window glows meanwhile.
    private(set) var assistantRequestsInFlight = 0

    private(set) var shells: [UUID: ShellSession] = [:]
    /// Open conversations with AI agent CLIs, by session.
    var agentChats: [UUID: AgentChat] = [:]
    /// Sessions whose open conversation or program card is on screen; the
    /// activity bar shows only when it isn't.
    var visibleActivityCards: Set<UUID> = []
    /// Apple Intelligence's conversation in each session, with its memory.
    @ObservationIgnored var assistantConversations: [UUID: AssistantConversation] = [:]

    @ObservationIgnored let modelContext: ModelContext
    @ObservationIgnored let notifications = NotificationService()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTasks: [UUID: Task<Void, Never>] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        try? ShellIntegration.install()
        repairInterruptedEntries()
        // The tool catalogs download in the background; tests stay offline.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil, AppSettings.assistantEnabled {
            AssistantEngine.prewarm()
            if AppSettings.searchesToolsOnline {
                Task.detached(priority: .utility) { await ToolKnowledge.shared.prepare() }
            }
            // What's installed changes rarely: read it before the first request.
            Task.detached(priority: .utility) { _ = await InstalledPackages.shared.brew() }
        }
        notifications.onOpenSession = { [weak self] id in
            self?.selectedSessionID = id
        }
        let sessions = (try? modelContext.fetch(FetchDescriptor<TerminalSession>(
            sortBy: [SortDescriptor(\.lastActivity, order: .reverse)]
        ))) ?? []
        if let first = sessions.first {
            selectedSessionID = first.id
        } else {
            selectedSessionID = createSession().id
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            nameUntitledSessions(sessions)
        }
    }

    /// Sessions from before titles existed get one from their first request.
    private func nameUntitledSessions(_ sessions: [TerminalSession]) {
        for session in sessions where session.customName == nil && session.autoName == nil {
            let entries = session.entries.sorted { $0.startedAt < $1.startedAt }
            if let agent = entries.first(where: { $0.kind == .agentStart || AICommandLine.isAgent($0.command) }) {
                session.autoName = AgentKind(rawValue: ShellSession.firstWord(of: agent.command))?.displayName
                    ?? ShellSession.firstWord(of: agent.command)
            }
            if let request = entries.first(where: { ($0.kind == .assistant || $0.kind == .agent)
                && AssistantEngine.keywords(in: AssistantEngine.normalized($0.command)).filter({ $0.count >= 3 }).count >= 2 })?.command {
                nameSessionIfNeeded(session, from: request)
            }
        }
        save()
    }

    // MARK: - Sessions

    @discardableResult
    func createSession(directory: String? = nil) -> TerminalSession {
        let session = TerminalSession(directory: directory ?? NSHomeDirectory())
        modelContext.insert(session)
        save()
        selectedSessionID = session.id
        return session
    }

    func session(withID id: UUID?) -> TerminalSession? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<TerminalSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    var selectedSession: TerminalSession? { session(withID: selectedSessionID) }

    var selectedShell: ShellSession? {
        guard let selectedSessionID else { return nil }
        return shells[selectedSessionID]
    }

    var selectedShellDirectory: String? {
        selectedShell?.directory ?? selectedSession?.directory
    }

    /// Moves the selection up or down the sidebar (which is sorted by activity).
    func selectAdjacentSession(offset: Int) {
        let sessions = (try? modelContext.fetch(FetchDescriptor<TerminalSession>(
            sortBy: [SortDescriptor(\.lastActivity, order: .reverse)]
        ))) ?? []
        guard !sessions.isEmpty else { return }
        let index = sessions.firstIndex { $0.id == selectedSessionID } ?? 0
        let next = (index + offset + sessions.count) % sessions.count
        selectedSessionID = sessions[next].id
    }

    func delete(_ session: TerminalSession) {
        let id = session.id
        shells[id]?.terminate()
        shells[id] = nil
        let remaining = ((try? modelContext.fetch(FetchDescriptor<TerminalSession>(
            sortBy: [SortDescriptor(\.lastActivity, order: .reverse)]
        ))) ?? []).filter { $0.id != id }
        modelContext.delete(session)
        save()
        if selectedSessionID == id {
            selectedSessionID = remaining.first?.id ?? createSession().id
        }
    }

    func rename(_ session: TerminalSession, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.customName = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func clearHistory(of session: TerminalSession) {
        let running = shells[session.id]?.live?.entryID
        for entry in session.entries where entry.id != running {
            modelContext.delete(entry)
        }
        session.lastCommand = nil
        // A clean chat starts a fresh conversation too.
        assistantConversations[session.id] = nil
        save()
    }

    // MARK: - Shells

    /// The shell for a session, started on first use.
    @discardableResult
    func shell(for session: TerminalSession) -> ShellSession {
        if let shell = shells[session.id] { return shell }
        let shell = ShellSession(id: session.id, directory: session.directory)
        shell.delegate = self
        shell.interactiveCommands = AppSettings.interactiveCommands
        shells[session.id] = shell
        shell.start()
        return shell
    }

    func restartShell(of session: TerminalSession) {
        let shell = shell(for: session)
        shell.interactiveCommands = AppSettings.interactiveCommands
        shell.restart()
    }

    var hasRunningCommands: Bool {
        shells.values.contains { $0.isBusy }
    }

    func terminateAll() {
        for shell in shells.values { shell.terminate() }
        flushPendingSave()
    }

    // MARK: - Commands

    /// Handles text from the composer: a new command, or input for the running one.
    func submit(_ text: String, in session: TerminalSession, confirmed: Bool = false, bypassAgentChat: Bool = false) {
        let shell = shell(for: session)
        if shell.isBusy {
            shell.sendLine(text)
            return
        }
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        // `agy`, `claude`, `codex` or `qwen` on their own open as a chat.
        if !bypassAgentChat, AppSettings.agentsAsChat, let kind = AgentKind(command: command),
           AgentProcess.executable(kind.rawValue, path: shell.pathEntries) != nil {
            startAgent(kind, command: command, in: session)
            return
        }

        if !confirmed, AppSettings.confirmRiskyCommands {
            // Deleting files always offers the recoverable option: the Trash.
            let trash = TrashConverter.isAvailable ? TrashConverter.trashCommand(for: command) : nil
            let risk = DangerDetector.risk(of: command) ?? trash.map { _ in
                CommandRisk(
                    title: String(localized: "Este comando borra archivos para siempre"),
                    explanation: String(localized: "No pasan por la Papelera. Si los mueves a la Papelera, podrás recuperarlos.")
                )
            }
            if var risk {
                // A rename Comando built: show exactly which files change.
                if let plan = RenamePlan(command: command) { risk.explanation = plan.preview(in: shell.directory) }
                // Not from an assistant reply unless runProposals says so.
                pendingProposalEntryID = nil
                pendingCommand = PendingCommand(command: command, sessionID: session.id, risk: risk, trashAlternative: trash)
                return
            }
        }

        if command == "clear" || command == "reset" {
            clearHistory(of: session)
            return
        }

        let entry = CommandEntry(command: command, directory: shell.directory, session: session)
        modelContext.insert(entry)
        session.lastActivity = entry.startedAt
        session.lastCommand = command
        // An AI agent opened in its own screen names the session after it.
        if session.customName == nil, session.autoName == nil, AICommandLine.isAgent(command) {
            session.autoName = AgentKind(rawValue: ShellSession.firstWord(of: command))?.displayName ?? ShellSession.firstWord(of: command)
        }
        save()
        shell.interactiveCommands = AppSettings.interactiveCommands
        shell.run(command, entryID: entry.id)
        schedulePermissionPrompt(for: entry.id, in: shell)
    }

    /// Runs the command the user confirmed in the risk alert.
    func confirmPendingCommand() {
        guard let pending = pendingCommand, let session = session(withID: pending.sessionID) else { return }
        pendingCommand = nil
        if let id = pendingProposalEntryID.take() { entry(withID: id)?.assistantRanAt = .now }
        submit(pending.command, in: session, confirmed: true)
    }

    /// Runs the recoverable version of a pending `rm`: move to the Trash.
    func moveToTrashInstead() {
        guard let pending = pendingCommand, let trash = pending.trashAlternative,
              let session = session(withID: pending.sessionID) else { return }
        pendingCommand = nil
        submit(trash, in: session, confirmed: true)
    }

    // MARK: - Assistant

    /// Sends a plain-language request to the assistant, with any attached files.
    func ask(_ text: String, attachments: [URL], in session: TerminalSession) {
        let request = IntentDetector.request(from: text)
        guard !request.isEmpty else { return }
        let shell = shell(for: session)
        let entry = CommandEntry(command: request, directory: shell.directory, session: session)
        entry.kind = .assistant
        entry.attachmentPaths = attachments.map { $0.path(percentEncoded: false) }
        modelContext.insert(entry)
        session.lastActivity = entry.startedAt
        session.lastCommand = "✨ " + request
        save()
        answer(entry, in: shell)
    }

    /// Answers the assistant's “which file?” and asks again with it attached.
    func provide(_ file: URL, to entry: CommandEntry) {
        guard let session = entry.session else { return }
        entry.attachmentPaths.append(file.path(percentEncoded: false))
        entry.finishedAt = nil
        entry.assistantExplanation = nil
        entry.assistantError = nil
        entry.assistantExtras = AssistantExtras()
        save()
        answer(entry, in: shell(for: session))
    }

    private func answer(_ entry: CommandEntry, in shell: ShellSession) {
        let executables = Set(ExecutableIndex.shared.names(for: shell.pathEntries))
        let directory = entry.directory
        let request = entry.command
        let entryID = entry.id
        let attachments = entry.attachmentPaths.map { URL(filePath: $0) }
        let path = shell.pathEntries
        let conversation = entry.session.map(assistantConversation(for:))
        assistantRequestsInFlight += 1
        Task { [weak self] in
            defer { self?.assistantRequestsInFlight -= 1 }
            let inventory = await ToolInventory.gather(directory: directory, executables: executables, attachments: attachments, path: path)
            // “Ahora en mp3” becomes the whole request, from what was said before.
            let standalone = await conversation?.standalone(request, inventory: inventory) ?? request
            // What to show, with every check; whatever happens, a reply arrives.
            let prepared = await AssistantEngine.firstResult(within: .seconds(40)) {
                await AssistantEngine.structuredReply(to: standalone, inventory: inventory)
            } ?? .failure(String(localized: "Esto me está tomando demasiado. Inténtalo de nuevo o dilo con otras palabras."))

            // Then said in the assistant's own words, as they come. The entry
            // is looked up each time: it may have been cleared meanwhile.
            var shown = false
            let spoken = await conversation?.speak(request: request, reply: prepared, inventory: inventory) { [weak self] text in
                guard let self, let entry = self.entry(withID: entryID) else { return }
                if !shown {
                    shown = true
                    self.show(prepared, in: entry)
                }
                if prepared.error != nil { entry.assistantError = text } else { entry.assistantExplanation = text }
            }
            var fallback: String?
            if (!shown && prepared.answersItself) || (shown && spoken == nil) {
                fallback = prepared.answersItself ? await AssistantEngine.explain(standalone) : prepared.explanation
            }
            guard let self, let entry = self.entry(withID: entryID) else { return }
            if let session = entry.session { self.nameSessionIfNeeded(session, from: standalone) }
            if !shown {
                var reply = prepared
                // The question was left for the conversation; answer it the plain way.
                if reply.answersItself {
                    reply.explanation = fallback
                        ?? String(localized: "No tengo una buena respuesta para eso. ¿Me lo cuentas con otras palabras?")
                }
                self.show(reply, in: entry)
            } else if spoken == nil {
                // Stopped partway for safety: back to the prepared words.
                if prepared.error != nil { entry.assistantError = prepared.error } else { entry.assistantExplanation = fallback ?? "" }
            }
            self.save()
        }
    }

    private func show(_ reply: AssistantReply, in entry: CommandEntry) {
        entry.assistantExplanation = reply.explanation
        entry.proposals = reply.proposals
        entry.assistantError = reply.error
        entry.assistantExtras = reply.extras
        entry.finishedAt = .now
    }

    /// Gives an unnamed session a title from its first real request, so the
    /// sidebar doesn't read “Inicio” five times.
    func nameSessionIfNeeded(_ session: TerminalSession, from request: String) {
        guard session.customName == nil, session.autoName == nil || AgentKind.allCases.contains(where: { $0.displayName == session.autoName }) else { return }
        let id = session.id
        Task { [weak self] in
            guard let title = await AssistantEngine.sessionTitle(for: request),
                  let self, let session = self.session(withID: id), session.customName == nil else { return }
            session.autoName = title
            self.save()
        }
    }

    /// The session's conversation with Apple Intelligence, picking up from
    /// its last exchanges when it starts.
    func assistantConversation(for session: TerminalSession) -> AssistantConversation {
        if let conversation = assistantConversations[session.id] { return conversation }
        let history = session.entries
            .filter { $0.kind == .assistant && $0.isFinished }
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(3)
            .map { (request: $0.command, reply: $0.assistantError ?? $0.assistantExplanation ?? "") }
        let conversation = AssistantConversation(history: Array(history))
        assistantConversations[session.id] = conversation
        return conversation
    }

    /// Runs what the assistant proposed, as one visible command.
    func runProposals(of entry: CommandEntry) {
        guard let session = entry.session, !entry.proposals.isEmpty, !(shells[session.id]?.isBusy ?? false) else { return }
        submit(entry.proposals.map(\.command).joined(separator: " && "), in: session)
        // A risky command waits for the confirmation: “Ejecutado” only once it runs.
        if pendingCommand == nil {
            entry.assistantRanAt = .now
        } else {
            pendingProposalEntryID = entry.id
        }
    }

    func installPackage(_ package: String, for entry: CommandEntry) {
        let command = ToolCatalog.tool(named: package)?.installCommand ?? "brew install " + ShellEscape.quote(package)
        runInstall(command, for: entry)
    }

    /// Runs an install command (`brew install …`, `npm install -g …`) next to
    /// the entry that suggested it.
    func runInstall(_ command: String, for entry: CommandEntry) {
        guard let session = entry.session else { return }
        submit(command, in: idleSession(preferring: session))
    }

    /// Runs a package-manager command (from the Tools window) in the selected
    /// session, where its output stays visible.
    func runPackageCommand(_ command: String) {
        guard let session = selectedSession else { return }
        submit(command, in: idleSession(preferring: session))
    }

    /// The session itself when its shell is free; otherwise a new one in the
    /// same folder, so a command is never typed into a running program (an
    /// ssh session, a REPL or a password prompt).
    private func idleSession(preferring session: TerminalSession) -> TerminalSession {
        guard shells[session.id]?.isBusy ?? false else { return session }
        return createSession(directory: shells[session.id]?.directory ?? session.directory)
    }

    func rerun(_ entry: CommandEntry) {
        guard let session = entry.session else { return }
        selectedSessionID = session.id
        submit(entry.command, in: session)
    }

    // MARK: - Folders

    /// Moves the session's shell to `folder` by running a visible `cd`, so
    /// people see (and learn) the command behind the action.
    func navigate(to folder: String, in session: TerminalSession) {
        guard !(shells[session.id]?.isBusy ?? false) else { return }
        submit("cd " + ShellEscape.path(URL(filePath: folder, directoryHint: .isDirectory)), in: session)
    }

    func navigateUp(in session: TerminalSession) {
        let current = shells[session.id]?.directory ?? session.directory
        guard current != "/" else { return }
        submit("cd ..", in: session)
    }

    // MARK: - Search

    func search(_ text: String, in sessionID: UUID?) -> [CommandEntry] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let predicate: Predicate<CommandEntry>
        if let sessionID {
            predicate = #Predicate {
                $0.session?.id == sessionID
                    && ($0.command.localizedStandardContains(query) || $0.plainOutput.localizedStandardContains(query))
            }
        } else {
            predicate = #Predicate {
                $0.command.localizedStandardContains(query) || $0.plainOutput.localizedStandardContains(query)
            }
        }
        var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 200
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Persistence

    func save() {
        saveTask?.cancel()
        saveTask = Task { [modelContext] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            try? modelContext.save()
        }
    }

    /// Saves now instead of waiting for the debounced save.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        try? modelContext.save()
    }

    private func entry(withID id: UUID) -> CommandEntry? {
        var descriptor = FetchDescriptor<CommandEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Entries still marked as running belong to a previous launch.
    private func repairInterruptedEntries() {
        let descriptor = FetchDescriptor<CommandEntry>(predicate: #Predicate { $0.finishedAt == nil })
        for entry in (try? modelContext.fetch(descriptor)) ?? [] {
            entry.finishedAt = entry.startedAt
        }
        try? modelContext.save()
    }

    func markSelectedAsRead() {
        guard let session = selectedSession, session.unreadCount != 0 else { return }
        session.unreadCount = 0
        save()
    }

    private func schedulePermissionPrompt(for entryID: UUID, in shell: ShellSession) {
        permissionTasks[shell.id]?.cancel()
        permissionTasks[shell.id] = Task { [weak self, weak shell] in
            try? await Task.sleep(for: .seconds(AppSettings.notifyAfter))
            guard !Task.isCancelled, let shell, shell.live?.entryID == entryID else { return }
            self?.notifications.requestAuthorizationIfNeeded()
        }
    }
}

extension TerminalController: ShellSessionDelegate {
    func shellSession(_ shell: ShellSession, didChangeDirectory directory: String) {
        guard let session = session(withID: shell.id) else { return }
        session.directory = directory
        session.remember(directory)
        // The shell reports the new folder right after the command that changed it.
        if let latest = session.entries.max(by: { $0.startedAt < $1.startedAt }),
           latest.isFinished, latest.endDirectory == nil, latest.directory != directory {
            latest.endDirectory = directory
        }
        save()
    }

    func shellSession(_ shell: ShellSession, didFinish result: CommandResult) {
        permissionTasks[shell.id]?.cancel()
        guard let entry = entry(withID: result.entryID) else { return }
        var output = result.output
        if result.exitCode.map(Int.init) == ErrorExplainer.interruptedStatus {
            Self.removeInterruptEcho(from: &output)
        }
        entry.output = Data(output)
        entry.exitCode = result.exitCode.map(Int.init)
        entry.finishedAt = result.finishedAt
        entry.truncated = result.truncated
        entry.kind = result.wasInteractive ? .interactive : .command
        entry.transcript = result.transcript
        // Back from the agent's own screen: the chat starts it up again.
        if agentChats[shell.id] != nil, let session = entry.session { agentTerminalClosed(in: session) }
        let rendered = OutputRenderer.render(raw: output)
        RenderCache.shared[entry] = RenderCache.linked(rendered, for: entry)
        entry.plainOutput = String(rendered.plainText.prefix(CommandEntry.plainOutputLimit))
        if let hint = ErrorExplainer.hint(
            command: entry.command,
            output: rendered.plainText,
            exitCode: entry.exitCode,
            knownCommands: ExecutableIndex.shared.names(for: shell.pathEntries)
        ) {
            entry.hintMessage = hint.message
            entry.hintSuggestion = hint.suggestion
        }

        if Self.changesInstalledTools(entry.command) {
            ExecutableIndex.shared.invalidate()
            Task { await InstalledPackages.shared.invalidate() }
            installedToolsVersion += 1
        }

        guard let session = entry.session else { return }
        session.lastActivity = result.finishedAt
        let isVisible = NSApp.isActive && selectedSessionID == session.id
        if !isVisible {
            session.unreadCount += 1
        }
        if let duration = entry.duration, duration >= .seconds(AppSettings.notifyAfter), !isVisible {
            notifications.notifyFinished(
                command: entry.command,
                sessionName: session.displayName,
                sessionID: session.id,
                exitCode: entry.exitCode,
                duration: duration
            )
        }
        save()
    }

    /// The terminal echoes “^C” when a command is stopped; the receipt already
    /// says “Detenido”, so the echo is just noise.
    static func removeInterruptEcho(from output: inout [UInt8]) {
        let echo: [UInt8] = [0x5E, 0x43] // "^C"
        var end = output.count
        while end > 0, [0x0A, 0x0D, 0x20].contains(output[end - 1]) { end -= 1 }
        guard end >= echo.count, Array(output[(end - echo.count)..<end]) == echo else { return }
        output.removeSubrange((end - echo.count)...)
    }

    /// Installs, upgrades and removals that make the tool lists stale.
    static func changesInstalledTools(_ command: String) -> Bool {
        let managers: Set<String> = ["brew", "npm", "pnpm", "yarn", "bun", "pipx", "uv", "pip", "pip3", "gem", "cargo"]
        let verbs: Set<String> = ["install", "uninstall", "remove", "upgrade", "update", "add", "rm", "reinstall", "i", "un", "r", "up"]
        return command.split(separator: /&&|\|\||;/).contains { part in
            var words = part.split(separator: " ").map(String.init)
            // “nvm exec 24.1.0 npm uninstall -g x” runs npm.
            if words.first == "nvm", words.dropFirst().first == "exec" { words.removeFirst(min(3, words.count)) }
            guard let first = words.first, managers.contains(first) else { return false }
            return words.dropFirst().contains { verbs.contains($0) }
        }
    }

    func shellSessionDidExit(_ shell: ShellSession) {
        save()
    }
}
