import Foundation

/// A token together with the exact bytes it was decoded from.
nonisolated struct ParsedToken: Sendable {
    var token: TerminalToken
    var raw: [UInt8]
}
