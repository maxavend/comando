import Foundation

nonisolated enum TerminalToken: Equatable, Sendable {
    /// Printable text, already decoded from UTF-8.
    case text(String)
    /// A C0 control byte such as `\n`, `\r`, `\b` or `\t`.
    case control(UInt8)
    case csi(CSISequence)
    /// Operating System Command payload, without the `ESC ]` prefix or terminator.
    case osc(String)
    /// A two-byte escape such as `ESC 7` (save cursor). Intermediates are dropped.
    case escape(UInt8)
}
