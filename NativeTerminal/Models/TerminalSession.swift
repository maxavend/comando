import Foundation
import SwiftData

/// A conversation in the sidebar: one shell with its own folder and history.
@Model
final class TerminalSession {
    var id: UUID = UUID()
    /// Set when the user renames the session.
    var customName: String?
    /// A short title from the conversation (“Comprimir entrevista”), when the
    /// user hasn't named it. Otherwise the folder name is shown.
    var autoName: String?
    var directory: String = ""
    var createdAt: Date = Date.now
    var lastActivity: Date = Date.now
    var lastCommand: String?
    var unreadCount: Int = 0
    /// Folders visited in this session, most recent first.
    var recentDirectories: [String] = []
    /// Pinned sessions stay at the top of the sidebar.
    var isPinned: Bool = false
    /// Optional emoji shown in the avatar instead of the terminal symbol.
    var emoji: String?
    /// An SF Symbol the person chose for the avatar; otherwise one that
    /// fits the folder.
    var symbolName: String?
    /// Index into `SessionColor.all` for the avatar background.
    var colorIndex: Int = 0
    /// The AI agent this session is talking to, if a conversation is open,
    /// and the conversation's id so it resumes after relaunch.
    var agentName: String?
    var agentConversationID: String?
    var agentPermissionRawValue: String?

    @Relationship(deleteRule: .cascade, inverse: \CommandEntry.session)
    var entries: [CommandEntry] = []

    func remember(_ folder: String) {
        recentDirectories.removeAll { $0 == folder }
        recentDirectories.insert(folder, at: 0)
        if recentDirectories.count > 8 { recentDirectories.removeLast(recentDirectories.count - 8) }
    }

    init(directory: String) {
        self.directory = directory
    }

    /// The avatar's symbol: the one chosen, or one that fits the folder.
    @MainActor func avatarSymbol(for directory: String) -> String {
        symbolName ?? SessionSymbol.symbol(for: directory)
    }

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        if let autoName, !autoName.isEmpty { return autoName }
        return FolderName.display(directory)
    }
}
