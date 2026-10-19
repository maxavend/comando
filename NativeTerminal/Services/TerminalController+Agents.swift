import Foundation

/// Conversations with AI agent CLIs, shown as chat.
extension TerminalController {
    /// The session's open conversation. One saved before quitting reopens
    /// here and resumes when the next message goes out.
    func agentChat(for session: TerminalSession) -> AgentChat? {
        if let chat = agentChats[session.id] { return chat }
        guard let kind = session.agentName.flatMap(AgentKind.init(rawValue:)) else { return nil }
        let chat = makeChat(kind, for: session, conversationID: session.agentConversationID,
                            permission: session.agentPermissionRawValue.flatMap(AgentPermission.init(rawValue:)) ?? .ask)
        return chat
    }

    func startAgent(_ kind: AgentKind, command: String, in session: TerminalSession, resuming conversation: String? = nil) {
        endAgent(in: session)
        let shell = shell(for: session)
        let entry = CommandEntry(command: command, directory: shell.directory, session: session)
        entry.kind = .agentStart
        entry.agentName = kind.rawValue
        modelContext.insert(entry)
        session.agentName = kind.rawValue
        entry.agentConversationID = conversation
        session.agentConversationID = conversation
        session.agentPermissionRawValue = nil
        session.lastActivity = entry.startedAt
        session.lastCommand = command
        if session.customName == nil, session.autoName == nil { session.autoName = kind.displayName }
        _ = makeChat(kind, for: session, conversationID: conversation, permission: .ask)
        save()
    }

    private func makeChat(_ kind: AgentKind, for session: TerminalSession, conversationID: String?,
                          permission: AgentPermission) -> AgentChat {
        let shell = shell(for: session)
        let chat = AgentChat(kind: kind, sessionID: session.id, directory: shell.directory, path: shell.pathEntries,
                             conversationID: conversationID, permission: permission)
        chat.onChange = { [weak self] entry in
            let text = entry.agentReply.text
            if let session = entry.session {
                session.lastCommand = kind.rawValue + ": " + (text.isEmpty ? entry.command : String(text.prefix(80)))
            }
            self?.save()
        }
        chat.onNeedsTerminal = { [weak self, weak session] reason in
            guard let self, let session else { return }
            self.agentNeedsTerminal(session, reason: reason)
        }
        chat.onConversation = { [weak session] id in
            guard let session else { return }
            session.agentConversationID = id
            // The open start card keeps it, so the conversation can be resumed.
            session.entries.last { $0.kind == .agentStart && $0.finishedAt == nil }?.agentConversationID = id
        }
        agentChats[session.id] = chat
        chat.warmUp()
        return chat
    }

    /// Sends a message to the session's agent.
    func sendToAgent(_ text: String, in session: TerminalSession) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let chat = agentChat(for: session), !chat.isResponding else { return }
        if ["/salir", "/exit", "/quit", "exit", "salir"].contains(message.lowercased()) {
            endAgent(in: session)
            return
        }
        let shell = shell(for: session)
        let entry = CommandEntry(command: message, directory: shell.directory, session: session)
        entry.kind = .agent
        entry.agentName = chat.kind.rawValue
        modelContext.insert(entry)
        session.lastActivity = entry.startedAt
        session.lastCommand = chat.kind.rawValue + ": " + message
        save()
        // The first real message gives the conversation its title.
        nameSessionIfNeeded(session, from: message)
        chat.send(message, into: entry, directory: shell.directory, path: shell.pathEntries)
    }

    /// Lets the agent do more and asks it to try again.
    func allowAgent(_ permission: AgentPermission, in session: TerminalSession) {
        guard let chat = agentChat(for: session) else { return }
        chat.allow(permission)
        session.agentPermissionRawValue = permission.rawValue
        let message = permission == .edits
            ? String(localized: "Te doy permiso para crear y editar archivos. Inténtalo de nuevo.")
            : String(localized: "Te doy permiso para hacer lo que necesites. Inténtalo de nuevo.")
        sendToAgent(message, in: session)
    }

    func endAgent(in session: TerminalSession) {
        agentChats.removeValue(forKey: session.id)?.end()
        guard session.agentName != nil else { return }
        session.agentName = nil
        session.agentConversationID = nil
        session.agentPermissionRawValue = nil
        for entry in session.entries where entry.kind == .agentStart && entry.finishedAt == nil {
            entry.finishedAt = .now
        }
        save()
    }

    /// Continues the conversation in the CLI's own screen (to sign in, or
    /// for what doesn't fit in bubbles).
    /// The chat stays open: when the CLI quits, or with “Volver al chat”,
    /// the conversation goes on in bubbles.
    func openAgentInTerminal(in session: TerminalSession) {
        guard let chat = agentChat(for: session), !shell(for: session).isBusy else { return }
        chat.pause()
        submit(chat.kind.terminalCommand(resuming: chat.conversationID ?? session.agentConversationID),
               in: session, bypassAgentChat: true)
    }

    /// The CLI's screen closed: the chat picks the conversation up again.
    func agentTerminalClosed(in session: TerminalSession) {
        agentChats[session.id]?.warmUp()
    }

    /// The CLI needs its own screen: say why in the chat, and open it.
    func agentNeedsTerminal(_ session: TerminalSession, reason: String) {
        guard let chat = agentChats[session.id], !shell(for: session).isBusy else { return }
        let entry = session.entries.filter { $0.kind == .agent }.max { $0.startedAt < $1.startedAt }
        openAgentInTerminal(in: session)
        // After opening it, so stopping the turn doesn't write over the reason.
        if let entry, !entry.isDeleted {
            var reply = entry.agentReply
            // The CLI's own error text is in the notice already.
            reply.steps.removeAll { $0.kind == .text && reason.contains($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            reply.error = String(localized: "\(chat.kind.rawValue) necesita su pantalla para seguir (\(reason.prefix(120))). La abrí aquí abajo; cuando termines, vuelve al chat.")
            reply.finish()
            entry.agentReply = reply
            entry.finishedAt = entry.finishedAt ?? .now
            save()
        }
    }

    /// Closes the CLI's screen and goes back to chatting.
    func returnToAgentChat(in session: TerminalSession) {
        shell(for: session).quitForeground()
    }

    /// Picks up a conversation that was ended, from its start card.
    func resumeAgent(from entry: CommandEntry) {
        guard let session = entry.session, let kind = entry.agentKind else { return }
        startAgent(kind, command: entry.command, in: session, resuming: entry.agentConversationID)
    }
}

extension AgentKind {
    /// The command that opens the CLI's own screen, on the same conversation.
    nonisolated func terminalCommand(resuming conversation: String?) -> String {
        guard let conversation else { return rawValue }
        let id = ShellEscape.quote(conversation)
        return switch self {
        case .agy: "agy --conversation \(id)"
        case .claude, .qwen: "\(rawValue) --resume \(id)"
        case .codex: "codex resume \(id)"
        }
    }
}
