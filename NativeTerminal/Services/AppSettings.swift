import Foundation

/// User preference keys and defaults, shared by `@AppStorage` and the controller.
nonisolated enum AppSettings {
    static let fontSizeKey = "fontSize"
    static let notifyAfterKey = "notifyAfterSeconds"
    static let interactiveCommandsKey = "interactiveCommands"
    static let confirmRiskyCommandsKey = "confirmRiskyCommands"
    static let hasSeenWelcomeKey = "hasSeenWelcome"
    static let assistantEnabledKey = "assistantEnabled"
    static let searchesToolsOnlineKey = "searchesToolsOnline"

    static let defaultFontSize = 13.0
    static let defaultNotifyAfter = 10.0
    static let defaultInteractiveCommands = "ssh mosh python python3 node irb bun deno mysql psql sqlite3 redis-cli mongosh ftp sftp telnet bc"

    static var notifyAfter: Double {
        let value = UserDefaults.standard.double(forKey: notifyAfterKey)
        return value > 0 ? value : defaultNotifyAfter
    }

    /// Ask before commands that are hard to undo. On unless turned off.
    static var confirmRiskyCommands: Bool {
        UserDefaults.standard.object(forKey: confirmRiskyCommandsKey) as? Bool ?? true
    }

    /// Plain-language requests go to the assistant. On unless turned off.
    static var assistantEnabled: Bool {
        UserDefaults.standard.object(forKey: assistantEnabledKey) as? Bool ?? true
    }

    /// The assistant may download the Homebrew catalog and tldr examples, and
    /// search npm. On unless turned off.
    static var searchesToolsOnline: Bool {
        UserDefaults.standard.object(forKey: searchesToolsOnlineKey) as? Bool ?? true
    }

    static var interactiveCommands: Set<String> {
        let value = UserDefaults.standard.string(forKey: interactiveCommandsKey) ?? defaultInteractiveCommands
        return Set(value.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map(String.init))
    }
}
