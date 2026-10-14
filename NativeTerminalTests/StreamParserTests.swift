import Testing
@testable import NativeTerminal

struct StreamParserTests {
    private func tokens(_ chunks: [String]) -> [TerminalToken] {
        var parser = StreamParser()
        return chunks.flatMap { parser.feed(Array($0.utf8)).map(\.token) }
    }

    @Test func plainTextAndControls() {
        #expect(tokens(["hi\r\n"]) == [.text("hi"), .control(0x0D), .control(0x0A)])
    }

    @Test func csiWithParameters() {
        let result = tokens(["\u{1B}[1;31mred"])
        #expect(result == [
            .csi(CSISequence(marker: nil, params: [1, 31], intermediates: [], final: UInt8(ascii: "m"))),
            .text("red"),
        ])
    }

    @Test func privateModeMarker() {
        let result = tokens(["\u{1B}[?1049h"])
        guard case .csi(let csi) = result.first else {
            Issue.record("Expected CSI")
            return
        }
        #expect(csi.marker == UInt8(ascii: "?"))
        #expect(ShellSession.entersAlternateScreen(csi))
    }

    @Test func oscTerminatedByBellAndST() {
        #expect(tokens(["\u{1B}]133;D;0\u{07}"]) == [.osc("133;D;0")])
        #expect(tokens(["\u{1B}]7;file://host/Users\u{1B}\\"]) == [.osc("7;file://host/Users")])
    }

    @Test func sequenceSplitAcrossChunks() {
        let result = tokens(["ab\u{1B}]13", "3;C\u{07}c", "d"])
        #expect(result == [.text("ab"), .osc("133;C"), .text("c"), .text("d")])
    }

    @Test func utf8SplitAcrossChunks() {
        var parser = StreamParser()
        let bytes = Array("añ😀".utf8)
        var result: [TerminalToken] = []
        for byte in bytes {
            result += parser.feed([byte]).map(\.token)
        }
        let text = result.compactMap { token -> String? in
            if case .text(let string) = token { return string }
            return nil
        }.joined()
        #expect(text == "añ😀")
    }

    @Test func rawBytesArePreserved() {
        var parser = StreamParser()
        let input = Array("x\u{1B}[0mY\u{1B}]0;title\u{07}".utf8)
        let raw = parser.feed(input).flatMap(\.raw)
        #expect(raw == input)
    }
}
