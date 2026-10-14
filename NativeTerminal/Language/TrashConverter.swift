import Foundation

/// Turns an `rm` into the equivalent `trash` (macOS's /usr/bin/trash), so
/// files go to the Trash and can be recovered.
nonisolated enum TrashConverter {
    static let trashPath = "/usr/bin/trash"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: trashPath)
    }

    /// `rm -rf a "b c"` → `trash a "b c"`. Nil if it isn't a plain `rm`.
    static func trashCommand(for command: String) -> String? {
        let tokens = CommandExplainer.tokens(command)
        var words = tokens[...]
        if words.first == "sudo" { words = words.dropFirst() }
        guard words.first == "rm" else { return nil }
        // Pipes, redirects or chains change the meaning; leave those alone.
        guard !tokens.contains(where: { ["|", "||", "&&", ";", ">", ">>", "<", "&"].contains($0) }) else { return nil }
        var paths: [String] = []
        var endOfOptions = false
        for token in words.dropFirst() {
            if !endOfOptions && token == "--" { endOfOptions = true; continue }
            if !endOfOptions && token.hasPrefix("-") { continue }
            paths.append(token)
        }
        guard !paths.isEmpty else { return nil }
        return (["trash"] + paths).joined(separator: " ")
    }
}
