import Foundation

/// A risky command waiting for the user to confirm it.
struct PendingCommand: Identifiable {
    let id = UUID()
    let command: String
    let sessionID: UUID
    let risk: CommandRisk
    /// For `rm`: the same files moved to the Trash instead (recoverable).
    var trashAlternative: String?
}
