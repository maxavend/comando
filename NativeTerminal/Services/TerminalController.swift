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
    func submit(_ text: String, in session: TerminalSession) {
        let shell = shell(for: session)
        if shell.isBusy {
            shell.sendLine(text)
            return
        }
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

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

    func rerun(_ entry: CommandEntry) {
        guard let session = entry.session else { return }
        selectedSessionID = session.id
        submit(entry.command, in: session)
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
        save()
    }

    func shellSession(_ shell: ShellSession, didFinish result: CommandResult) {
        permissionTasks[shell.id]?.cancel()
        guard let entry = entry(withID: result.entryID) else { return }
        entry.output = Data(result.output)
        entry.exitCode = result.exitCode.map(Int.init)
        entry.finishedAt = result.finishedAt
        entry.truncated = result.truncated
        entry.kind = result.wasInteractive ? .interactive : .command
        entry.transcript = result.transcript
        let rendered = OutputRenderer.render(raw: result.output)
        RenderCache.shared[entry] = rendered
        entry.plainOutput = String(rendered.plainText.prefix(CommandEntry.plainOutputLimit))

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

    func shellSessionDidExit(_ shell: ShellSession) {
        save()
    }
}
