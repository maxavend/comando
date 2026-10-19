import Foundation

/// What an agent CLI reports, the same for every CLI.
nonisolated enum AgentEvent: Equatable, Sendable {
    /// The conversation's id, to resume it later.
    case conversation(String)
    case text(String)
    case toolStarted(id: String, name: String, input: [String: String])
    case toolFinished(id: String, output: String?, failed: Bool)
    /// The turn ended. `denied` names actions the agent wasn't allowed to do.
    case turnFinished(denied: [String], error: String?)
    case failed(String)
}

/// Turns the lines a CLI prints into events.
nonisolated protocol AgentOutputParser {
    mutating func parse(_ line: String) -> [AgentEvent]
}

nonisolated private func object(_ line: String) -> [String: Any]? {
    guard let data = line.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

/// Only the string-valued parameters, which is what the cards show.
nonisolated private func strings(_ value: Any?) -> [String: String] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    var result: [String: String] = [:]
    for (key, value) in dictionary {
        if let text = value as? String { result[key] = text }
        else if let number = value as? NSNumber { result[key] = number.stringValue }
    }
    return result
}

/// Antigravity CLI (`agy --output-format=stream-json`): `step_update`
/// events with text deltas and tool steps, and a `result` per turn.
nonisolated struct AgyParser: AgentOutputParser {
    mutating func parse(_ line: String) -> [AgentEvent] {
        guard let json = object(line), let event = json["event"] as? String else { return [] }
        switch event {
        case "init":
            return (json["conversation_id"] as? String).map { [.conversation($0)] } ?? []
        case "step_update":
            guard let step = json["step_update"] as? [String: Any] else { return [] }
            let state = step["state"] as? String ?? ""
            switch step["step_type"] as? String {
            case "agent_response":
                return (step["text_delta"] as? String).map { [.text($0)] } ?? []
            case "tool":
                let id = "\(step["step_index"] ?? "")"
                let info = step["tool_info"] as? [String: Any] ?? [:]
                let name = step["tool_name"] as? String ?? info["name"] as? String ?? "tool"
                if state == "ACTIVE" {
                    return [.toolStarted(id: id, name: name, input: strings(info["parameters"]))]
                }
                let error = (info["error"] as? [String: Any])?["message"] as? String
                return [.toolFinished(id: id, output: info["output"] as? String ?? error, failed: state == "ERROR")]
            default:
                return []
            }
        case "result":
            guard let result = json["result"] as? [String: Any] else { return [] }
            let denied = (result["denied_actions"] as? [[String: Any]] ?? []).compactMap { $0["action"] as? String }
            let failed = result["status"] as? String == "ERROR"
            return [.turnFinished(denied: denied, error: failed ? (result["error"] as? String ?? "") : nil)]
        default:
            return []
        }
    }
}

/// Claude Code and Qwen Code (`--output-format stream-json`): text arrives
/// as stream events when partial messages are on, and as whole assistant
/// messages otherwise; tool results come back as user messages.
nonisolated struct ClaudeStreamParser: AgentOutputParser {
    /// Whether this turn's text already arrived in pieces.
    private var streamedText = false

    mutating func parse(_ line: String) -> [AgentEvent] {
        guard let json = object(line), let type = json["type"] as? String else { return [] }
        switch type {
        case "system":
            guard json["subtype"] as? String == "init" else { return [] }
            return (json["session_id"] as? String).map { [.conversation($0)] } ?? []
        case "stream_event":
            guard let event = json["event"] as? [String: Any], event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return [] }
            streamedText = true
            return [.text(text)]
        case "assistant":
            let blocks = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            var events: [AgentEvent] = []
            for block in blocks {
                switch block["type"] as? String {
                case "text" where !streamedText:
                    if let text = block["text"] as? String { events.append(.text(text)) }
                case "tool_use":
                    events.append(.toolStarted(id: block["id"] as? String ?? "", name: block["name"] as? String ?? "tool",
                                               input: strings(block["input"])))
                default:
                    break
                }
            }
            return events
        case "user":
            let blocks = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { block in
                guard block["type"] as? String == "tool_result" else { return nil }
                let output: String? = if let text = block["content"] as? String {
                    text
                } else {
                    (block["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
                }
                return .toolFinished(id: block["tool_use_id"] as? String ?? "", output: output, failed: block["is_error"] as? Bool ?? false)
            }
        case "result":
            streamedText = false
            let denied = (json["permission_denials"] as? [[String: Any]] ?? []).compactMap { $0["tool_name"] as? String }
            let isError = json["is_error"] as? Bool ?? false
            let message = json["result"] as? String ?? (json["subtype"] as? String ?? "")
            return [.turnFinished(denied: denied, error: isError ? message : nil)]
        default:
            return []
        }
    }
}

/// Codex (`codex exec --json`): items that start and complete, and a turn
/// that completes or fails.
nonisolated struct CodexParser: AgentOutputParser {
    mutating func parse(_ line: String) -> [AgentEvent] {
        guard let json = object(line), let type = json["type"] as? String else { return [] }
        switch type {
        case "thread.started":
            return (json["thread_id"] as? String).map { [.conversation($0)] } ?? []
        case "item.started", "item.completed":
            guard let item = json["item"] as? [String: Any] else { return [] }
            let id = item["id"] as? String ?? ""
            let done = type == "item.completed"
            switch item["type"] as? String {
            case "agent_message":
                return done ? (item["text"] as? String).map { [.text($0)] } ?? [] : []
            case "command_execution":
                let input = ["command": item["command"] as? String ?? ""]
                guard done else { return [.toolStarted(id: id, name: "command_execution", input: input)] }
                let exit = item["exit_code"] as? Int ?? 0
                return [.toolStarted(id: id, name: "command_execution", input: input),
                        .toolFinished(id: id, output: item["aggregated_output"] as? String, failed: exit != 0)]
            case "file_change":
                guard done else { return [] }
                let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                return [.toolStarted(id: id, name: "file_change", input: ["path": paths.joined(separator: ", ")]),
                        .toolFinished(id: id, output: nil, failed: item["status"] as? String == "failed")]
            default:
                return []
            }
        case "turn.completed":
            return [.turnFinished(denied: [], error: nil)]
        case "turn.failed":
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            return [.turnFinished(denied: [], error: Self.readable(message))]
        case "error":
            return []
        default:
            return []
        }
    }

    /// Codex wraps API errors in JSON inside the message.
    static func readable(_ message: String) -> String {
        guard let inner = message.data(using: .utf8).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
              let error = inner["error"] as? [String: Any], let text = error["message"] as? String else { return message }
        return text
    }
}
