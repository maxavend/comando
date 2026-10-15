import Foundation

/// Tells a shell command (“git status”) from a request in plain words
/// (“sube esto a GitHub”).
nonisolated enum IntentDetector {
    private static let builtins: Set<String> = [
        "cd", "echo", "export", "source", "alias", "unalias", "exit", "history", "jobs", "fg", "bg",
        "pushd", "popd", "pwd", "type", "which", "set", "unset", "eval", "exec", "time", "for", "if", "while",
    ]

    static func isPlainLanguage(_ text: String, knownCommands: Set<String>) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return false }
        // “?” forces the assistant, for requests that start with a command name.
        if trimmed.hasPrefix("?") { return true }

        let words = trimmed.split(separator: " ").map(String.init)
        guard let first = words.first else { return false }
        if words.count == 1 {
            // “Hola”, “gracias” or “ayuda” on their own, unless a program has that name.
            let word = AssistantEngine.normalized(trimmed)
            return !knownCommands.contains(first)
                && (AssistantEngine.isGreeting(word) || AssistantEngine.isThanks(word) || AppGuide.topic(for: trimmed) != nil)
        }
        if first.contains("/") || first.contains("=") || first.hasPrefix(".") || first.hasPrefix("~") || first.hasPrefix("$") {
            return false
        }
        if knownCommands.contains(first) || builtins.contains(first) { return false }
        // Shell syntax means a command, even with an unknown program.
        if ["|", ">", "&&", ";", " -", "$(", "`"].contains(where: { trimmed.contains($0) }) { return false }
        return true
    }

    /// The request without a leading “?”.
    static func request(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("?") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return trimmed
    }
}
