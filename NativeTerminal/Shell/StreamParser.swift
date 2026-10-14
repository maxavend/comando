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

/// A token together with the exact bytes it was decoded from.
nonisolated struct ParsedToken: Sendable {
    var token: TerminalToken
    var raw: [UInt8]
}

/// Incremental tokenizer for the byte stream coming out of the PTY.
///
/// It is resilient to escape sequences and UTF-8 code points split across
/// chunk boundaries, which is the normal case when reading from a PTY.
nonisolated struct StreamParser: Sendable {
    private enum State: Sendable {
        case ground
        case escape
        case escapeIntermediate
        case csi
        case osc
        case oscEscape
        case string        // DCS / SOS / PM / APC: skipped until ST
        case stringEscape
    }

    private static let esc: UInt8 = 0x1B
    private static let bel: UInt8 = 0x07
    private static let maxSequenceLength = 64 * 1024

    private var state: State = .ground
    private var text: [UInt8] = []
    private var sequence: [UInt8] = []
    private var payload: [UInt8] = []

    init() {}

    mutating func feed<C: Collection>(_ bytes: C) -> [ParsedToken] where C.Element == UInt8 {
        var tokens: [ParsedToken] = []
        for byte in bytes {
            consume(byte, into: &tokens)
        }
        flushText(into: &tokens, final: false)
        return tokens
    }

    private mutating func consume(_ byte: UInt8, into tokens: inout [ParsedToken]) {
        switch state {
        case .ground:
            if byte == Self.esc {
                flushText(into: &tokens, final: true)
                sequence = [byte]
                state = .escape
            } else if byte < 0x20 || byte == 0x7F {
                flushText(into: &tokens, final: true)
                tokens.append(ParsedToken(token: .control(byte), raw: [byte]))
            } else {
                text.append(byte)
            }

        case .escape:
            sequence.append(byte)
            switch byte {
            case UInt8(ascii: "["):
                state = .csi
            case UInt8(ascii: "]"):
                payload = []
                state = .osc
            case UInt8(ascii: "P"), UInt8(ascii: "X"), UInt8(ascii: "^"), UInt8(ascii: "_"):
                state = .string
            case 0x20...0x2F:
                state = .escapeIntermediate
            case Self.esc:
                // ESC ESC: restart the sequence.
                sequence = [byte]
            default:
                emit(.escape(byte), into: &tokens)
            }

        case .escapeIntermediate:
            sequence.append(byte)
            if (0x30...0x7E).contains(byte) {
                emit(.escape(byte), into: &tokens)
            } else if !(0x20...0x2F).contains(byte) {
                state = .ground
                sequence = []
            }

        case .csi:
            sequence.append(byte)
            if (0x40...0x7E).contains(byte) {
                emit(.csi(Self.parseCSI(sequence)), into: &tokens)
            } else if byte < 0x20 {
                // C0 controls inside a CSI are executed immediately.
                sequence.removeLast()
                tokens.append(ParsedToken(token: .control(byte), raw: [byte]))
            } else if sequence.count > Self.maxSequenceLength {
                state = .ground
                sequence = []
            }

        case .osc:
            sequence.append(byte)
            if byte == Self.bel {
                emitOSC(into: &tokens)
            } else if byte == Self.esc {
                state = .oscEscape
            } else if payload.count < Self.maxSequenceLength {
                payload.append(byte)
            }

        case .oscEscape:
            sequence.append(byte)
            if byte == UInt8(ascii: "\\") {
                emitOSC(into: &tokens)
            } else {
                payload.append(Self.esc)
                payload.append(byte)
                state = .osc
            }

        case .string:
            sequence.append(byte)
            if byte == Self.esc {
                state = .stringEscape
            } else if byte == Self.bel {
                emitSkipped(into: &tokens)
            }

        case .stringEscape:
            sequence.append(byte)
            if byte == UInt8(ascii: "\\") {
                emitSkipped(into: &tokens)
            } else {
                state = .string
            }
        }
    }

    private mutating func emit(_ token: TerminalToken, into tokens: inout [ParsedToken]) {
        tokens.append(ParsedToken(token: token, raw: sequence))
        sequence = []
        state = .ground
    }

    private mutating func emitOSC(into tokens: inout [ParsedToken]) {
        let string = String(decoding: payload, as: UTF8.self)
        payload = []
        emit(.osc(string), into: &tokens)
    }

    /// DCS/APC/etc. are not rendered in the chat, but their bytes are kept so the
    /// embedded terminal still receives them.
    private mutating func emitSkipped(into tokens: inout [ParsedToken]) {
        tokens.append(ParsedToken(token: .osc(""), raw: sequence))
        sequence = []
        state = .ground
    }

    /// Emits buffered text. When `final` is false a trailing incomplete UTF-8
    /// sequence is kept for the next chunk.
    private mutating func flushText(into tokens: inout [ParsedToken], final: Bool) {
        guard !text.isEmpty else { return }
        var cut = text.count
        if !final {
            cut = Self.completeUTF8Prefix(text)
            guard cut > 0 else { return }
        }
        let chunk = Array(text[..<cut])
        text.removeFirst(cut)
        tokens.append(ParsedToken(token: .text(String(decoding: chunk, as: UTF8.self)), raw: chunk))
    }

    /// Length of the longest prefix that does not end in the middle of a UTF-8 code point.
    static func completeUTF8Prefix(_ bytes: [UInt8]) -> Int {
        let count = bytes.count
        var index = count - 1
        var continuation = 0
        while index >= 0, continuation < 3, bytes[index] & 0xC0 == 0x80 {
            continuation += 1
            index -= 1
        }
        guard index >= 0 else { return count }
        let lead = bytes[index]
        let expected: Int
        switch lead {
        case 0xC0...0xDF: expected = 1
        case 0xE0...0xEF: expected = 2
        case 0xF0...0xF7: expected = 3
        default: return count
        }
        return continuation < expected ? index : count
    }

    static func parseCSI(_ bytes: [UInt8]) -> CSISequence {
        // bytes = ESC [ <marker?> <params> <intermediates> <final>
        var body = bytes.dropFirst(2)
        let final = body.popLast() ?? 0
        var marker: UInt8?
        if let first = body.first, (0x3C...0x3F).contains(first) {
            marker = first
            body = body.dropFirst()
        }
        var params: [Int?] = []
        var intermediates: [UInt8] = []
        var current: Int?
        var sawParam = false
        for byte in body {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                current = (current ?? 0) &* 10 &+ Int(byte - UInt8(ascii: "0"))
                sawParam = true
            case UInt8(ascii: ";"), UInt8(ascii: ":"):
                params.append(current)
                current = nil
                sawParam = true
            case 0x20...0x2F:
                intermediates.append(byte)
            default:
                break
            }
        }
        if sawParam { params.append(current) }
        return CSISequence(marker: marker, params: params, intermediates: intermediates, final: final)
    }
}
