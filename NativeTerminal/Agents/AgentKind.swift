import Foundation

/// An AI agent CLI that Comando can talk to as a chat: its own words in
/// bubbles and its tools as cards, instead of the screen it draws.
nonisolated enum AgentKind: String, Codable, CaseIterable, Sendable {
    case agy, claude, qwen, codex

    /// The agent a bare command starts (`agy`, `claude`…), if any.
    init?(command: String) {
        let words = command.trimmingCharacters(in: .whitespaces).split(separator: " ")
        // Only the bare name: `./claude` is some other program.
        guard words.count == 1, !words[0].contains("/"), let kind = AgentKind(rawValue: String(words[0])) else { return nil }
        self = kind
    }

    var displayName: String {
        switch self {
        case .agy: "Antigravity"
        case .claude: "Claude Code"
        case .qwen: "Qwen Code"
        case .codex: "Codex"
        }
    }

    /// How the CLI is driven.
    enum Transport: Sendable {
        /// One process for the whole conversation, one JSON message per line.
        case persistent
        /// A process per message that resumes the conversation by its id.
        case perTurn
    }

    var transport: Transport {
        switch self {
        case .agy, .claude: .persistent
        case .qwen, .codex: .perTurn
        }
    }

    /// Arguments to start the CLI headless. `conversation` resumes one;
    /// `message` is the prompt for per-turn CLIs.
    func arguments(conversation: String?, permission: AgentPermission, message: String?) -> [String] {
        switch self {
        case .agy:
            var args = ["--input-format=stream-json", "--output-format=stream-json", "--print="]
            if let conversation { args += ["--conversation", conversation] }
            switch permission {
            case .ask: break
            case .edits: args += ["--mode", "accept-edits"]
            case .all: args += ["--mode", "auto"]
            }
            return args
        case .claude:
            var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            if let conversation { args += ["--resume", conversation] }
            switch permission {
            case .ask: break
            case .edits: args += ["--permission-mode", "acceptEdits"]
            case .all: args += ["--permission-mode", "bypassPermissions"]
            }
            return args
        case .qwen:
            var args = ["-p", message ?? "", "-o", "stream-json"]
            if let conversation { args += ["--resume", conversation] }
            return args
        case .codex:
            var args = ["exec"]
            if let conversation { args += ["resume", conversation] }
            args += ["--json", "--skip-git-repo-check"]
            switch permission {
            case .ask: break
            case .edits: args += ["-s", "workspace-write"]
            case .all: args += ["--dangerously-bypass-approvals-and-sandbox"]
            }
            args.append(message ?? "")
            return args
        }
    }

    /// One user message for persistent CLIs, as the line they read.
    func inputLine(_ message: String) -> String {
        let object: [String: Any] = switch self {
        case .agy: ["event": "user", "message": ["content": message]]
        default: ["type": "user", "message": ["role": "user", "content": message]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Whether the CLI can be given more permissions from the command line.
    var hasPermissionModes: Bool { self != .qwen }

    func makeParser() -> any AgentOutputParser {
        switch self {
        case .agy: AgyParser()
        case .claude, .qwen: ClaudeStreamParser()
        case .codex: CodexParser()
        }
    }
}

/// What the agent may do without asking, for this conversation.
nonisolated enum AgentPermission: String, Codable, Sendable {
    /// Headless CLIs can't ask, so anything that needs permission is denied
    /// and shown as a card with buttons.
    case ask
    case edits
    case all
}
