import AppKit
import SwiftUI

/// Terminal colors that adapt to light and dark appearance, so output stays
/// legible on the system bubble background in both modes.
nonisolated enum TerminalPalette {
    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        }
    }

    private static func srgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// The 16 ANSI colors. Black and white are mapped to label colors so they
    /// never disappear against the bubble.
    static let ansi: [NSColor] = [
        .labelColor,                                              // 0 black
        dynamic(light: srgb(0xC4_1A_16), dark: srgb(0xFF_6B_63)), // 1 red
        dynamic(light: srgb(0x1F_8A_3B), dark: srgb(0x5F_D3_7A)), // 2 green
        dynamic(light: srgb(0x9A_6B_00), dark: srgb(0xF2_C8_4B)), // 3 yellow
        dynamic(light: srgb(0x0B_5F_D6), dark: srgb(0x6A_A9_FF)), // 4 blue
        dynamic(light: srgb(0xA2_2E_B8), dark: srgb(0xE0_8B_F0)), // 5 magenta
        dynamic(light: srgb(0x0E_7C_86), dark: srgb(0x5C_D6_E0)), // 6 cyan
        .secondaryLabelColor,                                     // 7 white
        .secondaryLabelColor,                                     // 8 bright black
        dynamic(light: srgb(0xE0_2F_28), dark: srgb(0xFF_8A_80)), // 9 bright red
        dynamic(light: srgb(0x2B_A3_4C), dark: srgb(0x8C_EE_A0)), // 10 bright green
        dynamic(light: srgb(0xB3_80_00), dark: srgb(0xFF_DE_7A)), // 11 bright yellow
        dynamic(light: srgb(0x2F_7B_F0), dark: srgb(0x9A_C5_FF)), // 12 bright blue
        dynamic(light: srgb(0xBF_4F_D4), dark: srgb(0xF0_B0_FA)), // 13 bright magenta
        dynamic(light: srgb(0x12_96_A1), dark: srgb(0x8D_EC_F2)), // 14 bright cyan
        .labelColor,                                              // 15 bright white
    ]

    static func nsColor(_ color: TermColor) -> NSColor {
        switch color {
        case .ansi(let index):
            return ansi[Int(index) & 0x0F]
        case .palette(let index):
            let value = Int(index)
            if value < 16 { return ansi[value] }
            if value >= 232 {
                let level = CGFloat(8 + (value - 232) * 10) / 255
                return NSColor(srgbRed: level, green: level, blue: level, alpha: 1)
            }
            let cube = value - 16
            let steps: [CGFloat] = [0, 95, 135, 175, 215, 255]
            return NSColor(
                srgbRed: steps[cube / 36] / 255,
                green: steps[(cube / 6) % 6] / 255,
                blue: steps[cube % 6] / 255,
                alpha: 1
            )
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }
}

/// A run of characters sharing one style.
nonisolated struct StyledRun: Sendable, Equatable {
    var text: String
    var style: TextStyle
}

/// The result of rendering a command's output, ready to display.
nonisolated struct RenderedOutput: Sendable {
    /// The tail of the output shown in the bubble.
    var preview: AttributedString
    /// Number of lines in the whole output (after trimming).
    var totalLines: Int
    /// Number of lines included in `preview`.
    var previewLines: Int
    var plainText: String

    var isEmpty: Bool { totalLines == 0 }
    var isClipped: Bool { previewLines < totalLines }

    static let empty = RenderedOutput(preview: AttributedString(), totalLines: 0, previewLines: 0, plainText: "")
}

nonisolated enum OutputRenderer {
    /// How many lines a bubble shows before offering “Show all”.
    static let previewLineLimit = 300

    static func buffer(from raw: [UInt8], screenRows: Int = 40) -> LineBuffer {
        var parser = StreamParser()
        var buffer = LineBuffer()
        buffer.screenRows = screenRows
        for token in parser.feed(raw) {
            buffer.apply(token.token)
        }
        return buffer
    }

    static func render(raw: [UInt8]) -> RenderedOutput {
        render(buffer(from: raw))
    }

    static func render(_ buffer: LineBuffer, previewLimit: Int = previewLineLimit) -> RenderedOutput {
        let lines = trimmedLines(buffer)
        let start = max(0, lines.count - previewLimit)
        var preview = AttributedString()
        for (offset, line) in lines[start...].enumerated() {
            if offset > 0 { preview.append(AttributedString("\n")) }
            for run in runs(in: line) {
                preview.append(attributed(run))
            }
        }
        let plain = lines.map { line in String(line.map(\.character)) }.joined(separator: "\n")
        return RenderedOutput(
            preview: preview,
            totalLines: lines.count,
            previewLines: lines.count - start,
            plainText: plain
        )
    }

    /// Renders only the last lines of a live buffer; cheap enough to run on
    /// every update while a command streams output.
    static func renderTail(_ buffer: LineBuffer, limit: Int = previewLineLimit) -> RenderedOutput {
        var tail = LineBuffer()
        tail.replaceLines(with: Array(buffer.lines.suffix(limit + 20)))
        var rendered = render(tail, previewLimit: limit)
        rendered.totalLines = max(rendered.totalLines, buffer.lineCount)
        return rendered
    }

    /// The full output as an AppKit string, for the “Show all” text view.
    static func fullAttributedString(raw: [UInt8], font: NSFont) -> NSAttributedString {
        let lines = trimmedLines(buffer(from: raw))
        let result = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: base)) }
            for run in runs(in: line) {
                var attributes = base
                let (foreground, background) = colors(for: run.style)
                if let foreground { attributes[.foregroundColor] = TerminalPalette.nsColor(foreground) }
                if let background { attributes[.backgroundColor] = TerminalPalette.nsColor(background) }
                if run.style.flags.contains(.inverse) && foreground == nil {
                    attributes[.foregroundColor] = NSColor.textBackgroundColor
                    attributes[.backgroundColor] = NSColor.labelColor
                }
                if run.style.flags.contains(.bold) { attributes[.font] = boldFont }
                if run.style.flags.contains(.italic) { attributes[.font] = italicFont }
                if run.style.flags.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if run.style.flags.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if run.style.flags.contains(.dim) {
                    let color = attributes[.foregroundColor] as? NSColor ?? .labelColor
                    attributes[.foregroundColor] = color.withAlphaComponent(0.6)
                }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
        }
        return result
    }

    /// Plain text with escape sequences removed, used for copy and search.
    static func plainText(raw: [UInt8]) -> String {
        trimmedLines(buffer(from: raw))
            .map { line in String(line.map(\.character)) }
            .joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Removes trailing blank cells and leading/trailing blank lines.
    static func trimmedLines(_ buffer: LineBuffer) -> [[Cell]] {
        var lines = buffer.lines.map { line -> [Cell] in
            var line = line
            while let last = line.last, last.character == " ", last.style.background == nil, !last.style.flags.contains(.inverse) {
                line.removeLast()
            }
            return line
        }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        while let first = lines.first, first.isEmpty { lines.removeFirst() }
        return lines
    }

    static func runs(in line: [Cell]) -> [StyledRun] {
        var runs: [StyledRun] = []
        for cell in line {
            if let last = runs.last, last.style == cell.style {
                runs[runs.count - 1].text.append(cell.character)
            } else {
                runs.append(StyledRun(text: String(cell.character), style: cell.style))
            }
        }
        return runs
    }

    private static func colors(for style: TextStyle) -> (TermColor?, TermColor?) {
        var foreground = style.foreground
        var background = style.background
        if style.flags.contains(.inverse) {
            swap(&foreground, &background)
        }
        // Bold + standard color renders as the bright variant, like most terminals.
        if style.flags.contains(.bold), case .ansi(let index)? = foreground, index < 8 {
            foreground = .ansi(index + 8)
        }
        return (foreground, background)
    }

    private static func attributed(_ run: StyledRun) -> AttributedString {
        var string = AttributedString(run.text)
        guard !run.style.isPlain else { return string }
        let (foreground, background) = colors(for: run.style)
        if let foreground {
            string.foregroundColor = Color(nsColor: TerminalPalette.nsColor(foreground))
        } else if run.style.flags.contains(.inverse) {
            string.foregroundColor = Color(nsColor: .textBackgroundColor)
        }
        if let background {
            string.backgroundColor = Color(nsColor: TerminalPalette.nsColor(background))
        } else if run.style.flags.contains(.inverse) {
            string.backgroundColor = Color(nsColor: .labelColor)
        }
        var intent: InlinePresentationIntent = []
        if run.style.flags.contains(.bold) { intent.insert(.stronglyEmphasized) }
        if run.style.flags.contains(.italic) { intent.insert(.emphasized) }
        if !intent.isEmpty { string.inlinePresentationIntent = intent }
        if run.style.flags.contains(.underline) { string.underlineStyle = .single }
        if run.style.flags.contains(.strikethrough) { string.strikethroughStyle = .single }
        if run.style.flags.contains(.dim) {
            let base = foreground.map(TerminalPalette.nsColor) ?? .labelColor
            string.foregroundColor = Color(nsColor: base.withAlphaComponent(0.6))
        }
        return string
    }
}
