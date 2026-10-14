import Foundation

nonisolated enum TermColor: Hashable, Sendable {
    /// One of the 16 standard ANSI colors (0–7 normal, 8–15 bright).
    case ansi(UInt8)
    /// xterm 256-color palette index (16–255).
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

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

nonisolated struct Cell: Hashable, Sendable {
    var character: Character
    var style: TextStyle

    static let blank = Cell(character: " ", style: .plain)
}

/// A minimal line-oriented terminal model used to render command output as
/// chat bubbles.
///
/// It is not a full emulator: it understands what commands typically print
/// when they are not full-screen programs — colors, carriage-return progress
/// bars, cursor movement within recent lines, erase sequences and man-page
/// style overstrike — and ignores the rest.
nonisolated struct LineBuffer: Sendable {
    private(set) var lines: [[Cell]] = [[]]
    private(set) var row = 0
    private(set) var column = 0
    private(set) var droppedLines = 0
    var style = TextStyle()
    /// Rows of the virtual screen; used to resolve absolute cursor positioning.
    var screenRows = 40
    var maxLines = 20_000

    private var savedCursor: (row: Int, column: Int)?
    private var pendingOverstrike = false

    init() {}

    var lineCount: Int { lines.count }

    var isEmpty: Bool {
        lines.allSatisfy { line in line.allSatisfy { $0.character == " " } }
    }

    mutating func apply(_ token: TerminalToken) {
        switch token {
        case .text(let string):
            for character in string {
                write(character)
            }
        case .control(let byte):
            control(byte)
        case .csi(let csi):
            apply(csi)
        case .escape(let final):
            switch final {
            case UInt8(ascii: "7"): savedCursor = (row, column)
            case UInt8(ascii: "8"):
                if let saved = savedCursor { moveTo(row: saved.row, column: saved.column) }
            case UInt8(ascii: "M"): moveTo(row: row - 1, column: column)
            case UInt8(ascii: "D"): lineFeed()
            case UInt8(ascii: "E"): lineFeed(); column = 0
            case UInt8(ascii: "c"): reset()
            default: break
            }
        case .osc:
            break
        }
    }

    mutating func replaceLines(with newLines: [[Cell]]) {
        lines = newLines.isEmpty ? [[]] : newLines
        row = lines.count - 1
        column = 0
    }

    mutating func apply(_ tokens: [TerminalToken]) {
        for token in tokens { apply(token) }
    }

    // MARK: - Writing

    private mutating func write(_ character: Character) {
        let isOverstrike = pendingOverstrike
        pendingOverstrike = false
        ensureColumn(column)
        var cell = Cell(character: character, style: style)
        if column < lines[row].count {
            if isOverstrike {
                let existing = lines[row][column]
                // man(1) style formatting: "x\bx" is bold, "_\bx" is underlined.
                if existing.character == character {
                    cell.style.flags.insert(.bold)
                } else if existing.character == "_" {
                    cell.style.flags.insert(.underline)
                } else if character == "_" {
                    cell = existing
                    cell.style.flags.insert(.underline)
                }
            }
            lines[row][column] = cell
        } else {
            lines[row].append(cell)
        }
        column += 1
    }

    private mutating func control(_ byte: UInt8) {
        switch byte {
        case 0x0A, 0x0B, 0x0C: // LF, VT, FF
            lineFeed()
            column = 0
        case 0x0D: // CR
            column = 0
        case 0x08: // BS
            if column > 0 {
                column -= 1
                pendingOverstrike = true
            }
        case 0x09: // TAB
            let next = (column / 8 + 1) * 8
            ensureColumn(next)
            column = next
        default:
            break
        }
    }

    private mutating func lineFeed() {
        row += 1
        if row >= lines.count {
            lines.append([])
            trimIfNeeded()
        }
    }

    private mutating func trimIfNeeded() {
        let overflow = lines.count - maxLines
        guard overflow > 0 else { return }
        lines.removeFirst(overflow)
        row = max(0, row - overflow)
        droppedLines += overflow
        savedCursor = nil
    }

    /// Pads the current line with blanks so `column` is addressable.
    private mutating func ensureColumn(_ column: Int) {
        let missing = column - lines[row].count
        if missing > 0 {
            lines[row].append(contentsOf: repeatElement(Cell(character: " ", style: style.backgroundOnly), count: missing))
        }
    }

    private mutating func moveTo(row newRow: Int, column newColumn: Int) {
        // The cursor can't leave the virtual screen upwards.
        let screenTop = max(0, lines.count - screenRows)
        row = max(newRow, screenTop)
        while row >= lines.count {
            lines.append([])
        }
        trimIfNeeded()
        column = max(0, newColumn)
    }

    private mutating func reset() {
        lines = [[]]
        row = 0
        column = 0
        style = TextStyle()
        savedCursor = nil
    }

    // MARK: - CSI

    private mutating func apply(_ csi: CSISequence) {
        guard csi.intermediates.isEmpty else { return }
        if csi.marker != nil { return } // private modes (e.g. ?25l) don't affect text

        let n = max(1, csi.param(0, default: 1))
        switch csi.final {
        case UInt8(ascii: "m"):
            applySGR(csi.params)
        case UInt8(ascii: "K"):
            eraseInLine(csi.param(0, default: 0))
        case UInt8(ascii: "J"):
            eraseInDisplay(csi.param(0, default: 0))
        case UInt8(ascii: "A"):
            moveTo(row: row - n, column: column)
        case UInt8(ascii: "B"):
            moveTo(row: row + n, column: column)
        case UInt8(ascii: "C"):
            column += n
        case UInt8(ascii: "D"):
            column = max(0, column - n)
        case UInt8(ascii: "E"):
            moveTo(row: row + n, column: 0)
        case UInt8(ascii: "F"):
            moveTo(row: row - n, column: 0)
        case UInt8(ascii: "G"), UInt8(ascii: "`"):
            column = max(0, csi.param(0, default: 1) - 1)
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
            let screenTop = max(0, lines.count - screenRows)
            let targetRow = screenTop + max(1, csi.param(0, default: 1)) - 1
            moveTo(row: targetRow, column: max(1, csi.param(1, default: 1)) - 1)
        case UInt8(ascii: "d"):
            let screenTop = max(0, lines.count - screenRows)
            moveTo(row: screenTop + max(1, csi.param(0, default: 1)) - 1, column: column)
        case UInt8(ascii: "X"):
            ensureColumn(column)
            let end = min(lines[row].count, column + n)
            for index in column..<end { lines[row][index] = Cell(character: " ", style: style.backgroundOnly) }
        case UInt8(ascii: "P"):
            if column < lines[row].count {
                lines[row].removeSubrange(column..<min(lines[row].count, column + n))
            }
        case UInt8(ascii: "@"):
            ensureColumn(column)
            lines[row].insert(contentsOf: repeatElement(Cell.blank, count: n), at: column)
        case UInt8(ascii: "s"):
            savedCursor = (row, column)
        case UInt8(ascii: "u"):
            if let saved = savedCursor { moveTo(row: saved.row, column: saved.column) }
        default:
            break
        }
    }

    private mutating func eraseInLine(_ mode: Int) {
        switch mode {
        case 0:
            if column < lines[row].count { lines[row].removeSubrange(column...) }
        case 1:
            ensureColumn(column)
            let end = min(column, lines[row].count - 1)
            if end >= 0 {
                for index in 0...end { lines[row][index] = Cell.blank }
            }
        case 2:
            lines[row] = []
        default:
            break
        }
    }

    private mutating func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseInLine(0)
            if row + 1 < lines.count { lines.removeSubrange((row + 1)...) }
        case 1:
            let screenTop = max(0, lines.count - screenRows)
            for index in screenTop..<row { lines[index] = [] }
            eraseInLine(1)
        case 2, 3:
            // `clear` inside a command's output: start the visible output over.
            reset()
        default:
            break
        }
    }

    private mutating func applySGR(_ params: [Int?]) {
        if params.isEmpty {
            style = TextStyle()
            return
        }
        var index = 0
        func next() -> Int? {
            index += 1
            return index < params.count ? params[index] : nil
        }
        while index < params.count {
            let code = params[index] ?? 0
            switch code {
            case 0: style = TextStyle()
            case 1: style.flags.insert(.bold)
            case 2: style.flags.insert(.dim)
            case 3: style.flags.insert(.italic)
            case 4: style.flags.insert(.underline)
            case 7: style.flags.insert(.inverse)
            case 9: style.flags.insert(.strikethrough)
            case 21, 22: style.flags.remove([.bold, .dim])
            case 23: style.flags.remove(.italic)
            case 24: style.flags.remove(.underline)
            case 27: style.flags.remove(.inverse)
            case 29: style.flags.remove(.strikethrough)
            case 30...37: style.foreground = .ansi(UInt8(code - 30))
            case 39: style.foreground = nil
            case 40...47: style.background = .ansi(UInt8(code - 40))
            case 49: style.background = nil
            case 90...97: style.foreground = .ansi(UInt8(code - 90 + 8))
            case 100...107: style.background = .ansi(UInt8(code - 100 + 8))
            case 38, 48:
                var color: TermColor?
                switch next() {
                case 5:
                    if let value = next() { color = Self.color256(value) }
                case 2:
                    let r = next() ?? 0, g = next() ?? 0, b = next() ?? 0
                    color = .rgb(UInt8(clamping: r), UInt8(clamping: g), UInt8(clamping: b))
                default:
                    break
                }
                if code == 38 { style.foreground = color } else { style.background = color }
            default:
                break
            }
            index += 1
        }
    }

    private static func color256(_ value: Int) -> TermColor {
        let clamped = UInt8(clamping: value)
        return clamped < 16 ? .ansi(clamped) : .palette(clamped)
    }
}

private extension TextStyle {
    /// Erased cells keep the current background color but nothing else.
    nonisolated var backgroundOnly: TextStyle {
        TextStyle(foreground: nil, background: background, flags: [])
    }
}
