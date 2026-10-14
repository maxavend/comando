import Foundation

nonisolated enum TermColor: Hashable, Sendable {
    /// One of the 16 standard ANSI colors (0–7 normal, 8–15 bright).
    case ansi(UInt8)
    /// xterm 256-color palette index (16–255).
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}
