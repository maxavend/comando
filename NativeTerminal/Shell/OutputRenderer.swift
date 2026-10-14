import AppKit
import SwiftUI

nonisolated enum OutputRenderer {
    /// How many lines a bubble shows before offering “Show all”.
    static let previewLineLimit = 300
    /// Lines shown while a command is still streaming output.
    static let liveLineLimit = 80

    static func buffer(from raw: [UInt8], screenRows: Int = 40, maxLines: Int = 20_000) -> LineBuffer {
        var parser = StreamParser()
        var buffer = LineBuffer()
        buffer.screenRows = screenRows
        buffer.maxLines = maxLines
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
            totalLines: lines.count + buffer.droppedLines,
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
        // Stored output is capped at 1 MB, so the full view can keep every line.
        let lines = trimmedLines(buffer(from: raw, maxLines: .max))
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
