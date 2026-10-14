import Foundation

nonisolated struct TextStyle: Hashable, Sendable {
    struct Flags: OptionSet, Hashable, Sendable {
        let rawValue: UInt8
        static let bold = Flags(rawValue: 1 << 0)
        static let dim = Flags(rawValue: 1 << 1)
        static let italic = Flags(rawValue: 1 << 2)
        static let underline = Flags(rawValue: 1 << 3)
        static let inverse = Flags(rawValue: 1 << 4)
        static let strikethrough = Flags(rawValue: 1 << 5)
    }

    var foreground: TermColor?
    var background: TermColor?
    var flags: Flags = []

    static let plain = TextStyle()

    var isPlain: Bool { self == .plain }
}
