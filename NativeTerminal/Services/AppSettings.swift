import Foundation

/// User preference keys and defaults, shared by `@AppStorage` and the controller.
nonisolated enum AppSettings {
    static let fontSizeKey = "fontSize"
    static let notifyAfterKey = "notifyAfterSeconds"
    static let interactiveCommandsKey = "interactiveCommands"

    static let defaultFontSize = 13.0
    static let defaultNotifyAfter = 10.0
    static let defaultInteractiveCommands = "ssh mosh python python3 node irb bun deno mysql psql sqlite3 redis-cli mongosh ftp sftp telnet bc"

    static var notifyAfter: Double {
        let value = UserDefaults.standard.double(forKey: notifyAfterKey)
        return value > 0 ? value : defaultNotifyAfter
    }

    static var interactiveCommands: Set<String> {
        let value = UserDefaults.standard.string(forKey: interactiveCommandsKey) ?? defaultInteractiveCommands
        return Set(value.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map(String.init))
    }
}
