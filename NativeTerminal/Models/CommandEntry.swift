import Foundation
import SwiftData

/// One message pair in the chat: the command the user sent and what the shell answered.
@Model
final class CommandEntry {
    enum Kind: String, Codable {
        case command
        case interactive
    }

    var id: UUID = UUID()
    var command: String = ""
    /// Raw output bytes, including ANSI styling, so colors survive relaunch.
    @Attribute(.externalStorage) var output: Data = Data()
    /// Output without escape sequences, for search. Capped in size.
    var plainOutput: String = ""
    var exitCode: Int?
    var startedAt: Date = Date.now
    var finishedAt: Date?
    var directory: String = ""
    var kindRawValue: String = Kind.command.rawValue
    /// Final text of an embedded-terminal program (e.g. an ssh or python session).
    var transcript: String?
    var truncated: Bool = false
    /// Folder the shell was in after the command, when the command changed it.
    var endDirectory: String?
    /// Plain-language explanation of a failure, and a command to try instead.
    var hintMessage: String?
    var hintSuggestion: String?
    var session: TerminalSession?

    init(command: String, directory: String, session: TerminalSession) {
        self.command = command
        self.directory = directory
        self.session = session
    }

    var kind: Kind {
        get { Kind(rawValue: kindRawValue) ?? .command }
        set { kindRawValue = newValue.rawValue }
    }

    var isFinished: Bool { finishedAt != nil }

    /// Finished without an exit code: the app quit or the shell restarted mid-command.
    var wasInterrupted: Bool { finishedAt != nil && exitCode == nil }

    var succeeded: Bool { exitCode == 0 }

    /// Stopped with ⌃C or the Stop button.
    var wasStopped: Bool { exitCode == ErrorExplainer.interruptedStatus }

    /// The folder change this command caused, if any.
    var movedTo: String? {
        guard let endDirectory, endDirectory != directory else { return nil }
        return endDirectory
    }

    var duration: Duration? {
        guard let finishedAt else { return nil }
        return .seconds(finishedAt.timeIntervalSince(startedAt))
    }

    static let plainOutputLimit = 64 * 1024
}
