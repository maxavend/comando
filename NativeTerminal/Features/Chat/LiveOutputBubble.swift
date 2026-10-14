import AppKit
import SwiftTerm
import SwiftUI

struct LiveOutputBubble: View {
    let live: LiveOutput

    var body: some View {
        // Reading `version` subscribes this view to throttled buffer updates.
        let _ = live.version
        let rendered = OutputRenderer.renderTail(live.buffer, limit: OutputRenderer.liveLineLimit)
        OutputBubble(output: OutputLinker.linkifyURLs(rendered.preview), plainText: rendered.plainText, monospaced: rendered.isTabular)
    }
}
