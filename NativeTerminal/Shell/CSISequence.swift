import Foundation

/// A CSI (Control Sequence Introducer) escape sequence, e.g. `ESC [ 1 ; 31 m`.
nonisolated struct CSISequence: Equatable, Sendable {
    /// Private marker such as `?`, `>`, `<` or `=` (e.g. `ESC [ ? 1049 h`).
    var marker: UInt8?
    /// Numeric parameters. Missing parameters are `nil`.
    var params: [Int?]
    var intermediates: [UInt8]
    var final: UInt8

    func param(_ index: Int, default value: Int) -> Int {
        guard index < params.count, let param = params[index] else { return value }
        return param
    }
}
