import SwiftUI

struct LiveOutputBubble: View {
    let live: LiveOutput

    var body: some View {
        // Reading `version` subscribes this view to throttled buffer updates.
        let _ = live.version
        let lines = Array(live.buffer.lines.suffix(OutputRenderer.liveLineLimit + 20))
        let progressLine = lines.lastIndex { line in line.contains { $0.character != " " } }
        let progress = progressLine.flatMap { ProgressParser.parse(String(lines[$0].map(\.character))) }

        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            if let progress, let progressLine {
                // The progress line becomes a native bar; the rest stays as text.
                let rest = Self.rendered(Array(lines[..<progressLine]))
                if !rest.isEmpty {
                    bubble(rest)
                }
                ProgressBubble(progress: progress)
            } else {
                bubble(Self.rendered(lines))
            }
        }
    }

    private func bubble(_ rendered: RenderedOutput) -> some View {
        OutputBubble(output: OutputLinker.linkifyURLs(rendered.preview), plainText: rendered.plainText,
                     monospaced: rendered.isTabular, lineCount: rendered.previewLines)
    }

    private static func rendered(_ lines: [[Cell]]) -> RenderedOutput {
        var buffer = LineBuffer()
        buffer.replaceLines(with: lines)
        return OutputRenderer.renderTail(buffer, limit: OutputRenderer.liveLineLimit)
    }
}
