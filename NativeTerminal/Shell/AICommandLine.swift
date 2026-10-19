import Foundation

/// Command-line AI agents (agy, Claude Code, Gemini CLI, Codex…). They draw
/// their own screen, but they are conversations: while one runs, the chat's
/// field keeps working and sends each message to it.
nonisolated enum AICommandLine {
    static let commands: Set<String> = [
        "agy", "claude", "gemini", "codex", "qwen", "aider", "opencode", "cursor-agent", "copilot",
        "goose", "amp", "crush", "droid", "kiro", "kiro-cli", "kimi", "cline", "auggie", "q", "ollama", "llm",
    ]

    /// Whether the command starts one of them (`agy`, `npx @openai/codex`,
    /// `ollama run llama3`…).
    static func isAgent(_ command: String) -> Bool {
        let words = command.split(separator: " ").map(String.init)
        guard let first = words.first.map({ ShellSession.firstWord(of: $0) }) else { return false }
        if ["npx", "bunx", "pnpx"].contains(first), let package = words.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            let name = package.split(separator: "/").last.map(String.init) ?? package
            return commands.contains(name) || name.hasSuffix("-cli") && commands.contains(String(name.dropLast(4)))
        }
        if first == "ollama" { return words.dropFirst().first == "run" }
        if first == "q" { return words.dropFirst().first == "chat" }
        return commands.contains(first)
    }
}
