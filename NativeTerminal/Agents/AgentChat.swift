import Foundation
import Observation

/// An open conversation with an agent CLI in one session. Each message is an
/// entry; the CLI's answer fills it as it streams in.
@MainActor @Observable
final class AgentChat {
    let kind: AgentKind
    let sessionID: UUID
    private(set) var conversationID: String?
    private(set) var permission: AgentPermission
    private(set) var isResponding = false
    /// The CLI is up and waiting for a message.
    private(set) var isReady = false
    /// Why the CLI couldn't start, when it quit before being ready.
    private(set) var startupError: String?

    @ObservationIgnored private var process: AgentProcess?
    @ObservationIgnored private var parser: any AgentOutputParser
    @ObservationIgnored private var current: CommandEntry?
    @ObservationIgnored private var directory: String
    @ObservationIgnored private var path: [String]
    /// Called when an entry changed, to save.
    @ObservationIgnored var onChange: (CommandEntry) -> Void = { _ in }
    @ObservationIgnored var onConversation: (String) -> Void = { _ in }
    /// The CLI is asking for something only its own screen can do (sign in,
    /// update, a yes/no question), or went silent: open the terminal.
    @ObservationIgnored var onNeedsTerminal: (String) -> Void = { _ in }
    @ObservationIgnored private var lastOutput = ContinuousClock.now
    @ObservationIgnored private var askedForTerminal = false

    init(kind: AgentKind, sessionID: UUID, directory: String, path: [String],
         conversationID: String? = nil, permission: AgentPermission = .ask) {
        self.kind = kind
        self.sessionID = sessionID
        self.directory = directory
        self.path = path
        self.conversationID = conversationID
        self.permission = permission
        parser = kind.makeParser()
    }

    var isInstalled: Bool { AgentProcess.executable(kind.rawValue, path: path) != nil }

    /// Starts the CLI ahead of the first message, so it's ready when the
    /// person writes. Per-message CLIs are ready right away.
    func warmUp() {
        startupError = nil
        guard kind.transport == .persistent else {
            isReady = isInstalled
            return
        }
        guard process?.isRunning != true else { return }
        isReady = false
        start(message: nil)
        // Some CLIs only introduce themselves after the first message.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, self.process?.isRunning == true else { return }
            self.isReady = true
        }
    }

    /// Sends a message; its answer streams into `entry`.
    func send(_ message: String, into entry: CommandEntry, directory: String, path: [String]) {
        guard !isResponding else { return }
        self.directory = directory
        self.path = path
        current = entry
        isResponding = true
        entry.agentReply = AgentReply()
        startupError = nil
        switch kind.transport {
        case .persistent:
            if process?.isRunning != true { start(message: nil) }
            process?.write(kind.inputLine(message))
        case .perTurn:
            start(message: message)
        }
        if process == nil {
            finishTurn(with: .failed(String(localized: "No se pudo abrir \(kind.rawValue).")))
            return
        }
        watchForSilence(of: entry)
    }

    /// Nothing at all for a long while: it's probably waiting on something
    /// only its own screen shows.
    private func watchForSilence(of entry: CommandEntry) {
        let id = entry.id
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.isResponding, self.current?.id == id, !self.askedForTerminal else { return }
                let quiet = ContinuousClock.now - self.lastOutput
                let hasOutput = self.current.map { !$0.agentReply.steps.isEmpty } ?? false
                if !hasOutput, quiet > .seconds(45) {
                    self.askedForTerminal = true
                    self.onNeedsTerminal(String(localized: "\(self.kind.rawValue) no respondió"))
                    return
                }
            }
        }
    }

    /// What the agent may do from now on. A persistent CLI restarts so the
    /// new mode applies; the conversation goes on.
    func allow(_ permission: AgentPermission) {
        self.permission = permission
        if kind.transport == .persistent {
            process?.closeInput()
            process = nil
        }
    }

    /// Stops the answer in progress.
    func stop() {
        process?.stop()
        if kind.transport == .persistent { process = nil }
        finishTurn(with: .turnFinished(denied: [], error: nil), stopped: true)
    }

    /// Lets the CLI's own screen take the conversation for a while: the
    /// headless process closes, and the next message resumes it.
    func pause() {
        if isResponding { stop() }
        process?.closeInput()
        process?.stop()
        process = nil
        isReady = false
    }

    /// Ends the conversation and the CLI with it.
    func end() {
        process?.closeInput()
        process?.stop()
        process = nil
        if isResponding { finishTurn(with: .turnFinished(denied: [], error: nil), stopped: true) }
    }

    // MARK: - Process

    private func start(message: String?) {
        guard let executable = AgentProcess.executable(kind.rawValue, path: path) else { return }
        parser = kind.makeParser()
        let arguments = kind.arguments(conversation: conversationID, permission: permission, message: message)
        // One stream, read in order: the text arrives in the order it was written.
        let (stream, continuation) = AsyncStream.makeStream(of: Output.self)
        let started = try? AgentProcess(
            executable: executable, arguments: arguments, directory: directory, path: path,
            onLine: { continuation.yield(.line($0)) },
            onErrorLine: { continuation.yield(.errorLine($0)) },
            onExit: { status, errors in
                continuation.yield(.exit(status, errors))
                continuation.finish()
            }
        )
        process = started
        lastOutput = .now
        askedForTerminal = false
        // One message per process: nothing more comes on its input. Codex and
        // Qwen wait for the input to end before they answer.
        if kind.transport == .perTurn { started?.closeInput() }
        Task { [weak self] in
            for await output in stream {
                guard let self else { return }
                switch output {
                case .line(let line): self.receive(line)
                case .errorLine(let line): self.noticeTerminalPrompt(in: line)
                case .exit(let status, let errors):
                    // A newer process may have replaced this one.
                    if self.process === started || self.process == nil { self.exited(status: status, errors: errors) }
                }
            }
        }
    }

    private enum Output: Sendable {
        case line(String)
        case errorLine(String)
        case exit(Int32, String)
    }

    /// Words of a screen that needs a person at the terminal.
    nonisolated static func needsTerminal(_ line: String) -> Bool {
        let text = line.lowercased()
        return ["update available", "press enter", "press any key", "do you trust", "trust this folder", "please log in",
                "please sign in", "not logged in", "log in to", "sign in to", "login required", "run `codex login`",
                "/login", "authenticate", "[y/n]", "(y/n)", "select an option", "open the following url",
                "device code", "api key is required", "oauth session expired"].contains(where: text.contains)
    }

    private func noticeTerminalPrompt(in line: String) {
        lastOutput = .now
        guard !askedForTerminal, Self.needsTerminal(line) else { return }
        askedForTerminal = true
        onNeedsTerminal(line.trimmingCharacters(in: .whitespaces))
    }

    private func receive(_ line: String) {
        lastOutput = .now
        // Not its JSON: a screen meant for a person, maybe one that needs them.
        if !line.trimmingCharacters(in: .whitespaces).hasPrefix("{") { noticeTerminalPrompt(in: line) }
        for event in parser.parse(line) {
            if case .conversation(let id) = event {
                conversationID = id
                isReady = true
                onConversation(id)
                continue
            }
            // Cleared from the chat meanwhile: nothing to write into.
            guard let entry = current, !entry.isDeleted else { continue }
            if case .turnFinished = event {
                finishTurn(with: event)
            } else {
                var reply = entry.agentReply
                reply.apply(event, agent: kind)
                entry.agentReply = reply
            }
        }
    }

    private func exited(status: Int32, errors: String) {
        process = nil
        isReady = kind.transport == .perTurn
        guard isResponding else {
            // Quit on its own before any message: say why.
            if status != 0, kind.transport == .persistent { startupError = Self.explain(errors, status: status, agent: kind) }
            return
        }
        // Quit before finishing the turn: explain with what it printed.
        finishTurn(with: .failed(Self.explain(errors, status: status, agent: kind)))
    }

    private func finishTurn(with event: AgentEvent, stopped: Bool = false) {
        guard let entry = current, !entry.isDeleted else {
            current = nil
            isResponding = false
            return
        }
        var reply = entry.agentReply
        reply.apply(event, agent: kind)
        if stopped, reply.steps.isEmpty { reply.error = String(localized: "Detenido") }
        entry.agentReply = reply
        entry.finishedAt = .now
        current = nil
        isResponding = false
        onChange(entry)
        // An error that only the CLI's screen can fix (signing in, updating).
        if !stopped, !askedForTerminal, let error = reply.error, Self.needsTerminal(error) {
            askedForTerminal = true
            onNeedsTerminal(error)
        }
    }

    /// The last meaningful lines of what the CLI printed on error.
    static func explain(_ errors: String, status: Int32, agent: AgentKind) -> String {
        let lines = errors.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("at ") && !$0.contains("node:internal") }
        if let line = lines.last(where: { $0.localizedCaseInsensitiveContains("error") }) ?? lines.last {
            return String(line.prefix(400))
        }
        return String(localized: "\(agent.rawValue) se cerró (código \(status)).")
    }
}
