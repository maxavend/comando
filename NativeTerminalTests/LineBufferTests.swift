import Testing
@testable import NativeTerminal

struct LineBufferTests {
    private func render(_ string: String) -> String {
        OutputRenderer.plainText(raw: Array(string.utf8))
    }

    private func buffer(_ string: String) -> LineBuffer {
        OutputRenderer.buffer(from: Array(string.utf8))
    }

    @Test func linesAndTrimming() {
        #expect(render("one\r\ntwo\r\n\r\n") == "one\ntwo")
    }

    @Test func carriageReturnOverwritesProgress() {
        #expect(render("10%\r50%\r100%\r\ndone\r\n") == "100%\ndone")
    }

    @Test func eraseLineAfterCarriageReturn() {
        #expect(render("downloading 12345\r\u{1B}[Kok\r\n") == "ok")
    }

    @Test func cursorUpRewritesPreviousLine() {
        #expect(render("a\r\nb\r\n\u{1B}[2A\u{1B}[2KA\r\n") == "A\nb")
    }

    @Test func tabsExpandToEightColumns() {
        #expect(render("a\tb") == "a       b")
    }

    @Test func sgrColorsAndReset() {
        let lines = OutputRenderer.trimmedLines(buffer("\u{1B}[1;32mok\u{1B}[0m!"))
        let runs = OutputRenderer.runs(in: lines[0])
        #expect(runs.count == 2)
        #expect(runs[0].text == "ok")
        #expect(runs[0].style.foreground == .ansi(2))
        #expect(runs[0].style.flags.contains(.bold))
        #expect(runs[1].style == .plain)
    }

    @Test func extendedColors() {
        let lines = OutputRenderer.trimmedLines(buffer("\u{1B}[38;5;208mA\u{1B}[38;2;1;2;3mB"))
        let runs = OutputRenderer.runs(in: lines[0])
        #expect(runs[0].style.foreground == .palette(208))
        #expect(runs[1].style.foreground == .rgb(1, 2, 3))
    }

    @Test func manPageOverstrike() {
        let lines = OutputRenderer.trimmedLines(buffer("N\u{08}NA\u{08}A _\u{08}x"))
        let cells = lines[0]
        #expect(String(cells.map(\.character)) == "NA x")
        #expect(cells[0].style.flags.contains(.bold))
        #expect(cells[3].style.flags.contains(.underline))
    }

    @Test func clearScreenStartsOver() {
        #expect(render("old\r\n\u{1B}[H\u{1B}[2Jnew") == "new")
    }

    @Test func lineLimitDropsOldest() {
        var buffer = LineBuffer()
        buffer.maxLines = 3
        for index in 0..<5 {
            buffer.apply(.text("\(index)"))
            buffer.apply(.control(0x0A))
        }
        #expect(buffer.droppedLines == 3)
        #expect(buffer.lines.map { String($0.map(\.character)) } == ["3", "4", ""])
    }
}
