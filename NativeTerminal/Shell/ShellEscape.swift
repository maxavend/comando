import Foundation

nonisolated enum ShellEscape {
    private static let safeCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./+@%:,=")

    /// Quotes a single argument for zsh only when needed.
    static func quote(_ argument: String) -> String {
        guard !argument.isEmpty else { return "''" }
        if argument.unicodeScalars.allSatisfy(safeCharacters.contains) {
            return argument
        }
        return "'" + argument.replacing("'", with: #"'\''"#) + "'"
    }

    /// A path ready to paste into a command line, using `~` for the home folder.
    static func path(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + quote(String(path.dropFirst(home.count + 1)))
        }
        return quote(path)
    }

    /// `/Users/me/Projects` → `~/Projects`, for display.
    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Backslash-escapes characters that are special to zsh: `My Folder` → `My\ Folder`.
    static func addBackslashes(_ text: String) -> String {
        var result = ""
        for character in text {
            if " '\"\\$`!&*()[]{}|;<>?#~^".contains(character) && !(character == "~" && result.isEmpty) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    static func removeBackslashes(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if character == "\\" && !escaping {
                escaping = true
                continue
            }
            escaping = false
            result.append(character)
        }
        return result
    }

    /// Expands a leading `~` to the home folder.
    static func expandTilde(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + path.dropFirst(1) }
        return path
    }
}
