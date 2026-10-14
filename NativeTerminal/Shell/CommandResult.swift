import Foundation
import Observation

/// What a finished command produced.
struct CommandResult {
    var entryID: UUID
    var exitCode: Int32?
    var output: [UInt8]
    var truncated: Bool
    var wasInteractive: Bool
    var transcript: String?
    var finishedAt: Date
}
