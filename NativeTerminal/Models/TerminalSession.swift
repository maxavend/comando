import Foundation
import SwiftData

/// A conversation in the sidebar: one shell with its own folder and history.
@Model
final class TerminalSession {
    var id: UUID = UUID()
    /// Set when the user renames the session; otherwise the folder name is shown.
    var customName: String?
    var directory: String = ""
    var createdAt: Date = Date.now
    var lastActivity: Date = Date.now
    var lastCommand: String?
    var unreadCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \CommandEntry.session)
    var entries: [CommandEntry] = []

    init(directory: String) {
        self.directory = directory
    }

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        let abbreviated = ShellEscape.abbreviate(directory)
        if abbreviated == "~" || abbreviated == "/" { return abbreviated }
        return URL(filePath: directory).lastPathComponent
    }
}
