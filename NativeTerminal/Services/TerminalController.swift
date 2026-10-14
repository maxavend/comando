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
    /// Presents the welcome guide.
    var isShowingWelcome = false

    private(set) var shells: [UUID: ShellSession] = [:]

    @ObservationIgnored let modelContext: ModelContext
    @ObservationIgnored let notifications = NotificationService()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTasks: [UUID: Task<Void, Never>] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        try? ShellIntegration.install()
        repairInterruptedEntries()
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
        try? modelContext.save()
    }

    // MARK: - Commands

    /// Handles text from the composer: a new command, or input for the running one.
    func submit(_ text: String, in session: TerminalSession, confirmed: Bool = false) {
        let shell = shell(for: session)
        if shell.isBusy {
            shell.sendLine(text)
            return
        }
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        if !confirmed, AppSettings.confirmRiskyCommands, let risk = DangerDetector.risk(of: command) {
            pendingCommand = PendingCommand(command: command, sessionID: session.id, risk: risk)
            return
        }

        if command == "clear" || command == "reset" {
            clearHistory(of: session)
            return
        }

        let entry = CommandEntry(command: command, directory: shell.directory, session: session)
        modelContext.insert(entry)
        session.lastActivity = entry.startedAt
        session.lastCommand = command
        save()
        shell.interactiveCommands = AppSettings.interactiveCommands
        shell.run(command, entryID: entry.id)
        schedulePermissionPrompt(for: entry.id, in: shell)
    }

    /// Runs the command the user confirmed in the risk alert.
    func confirmPendingCommand() {
        guard let pending = pendingCommand, let session = session(withID: pending.sessionID) else { return }
        pendingCommand = nil
        submit(pending.command, in: session, confirmed: true)
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

    func shellSessionDidExit(_ shell: ShellSession) {
        save()
    }
}
