import AppKit
import SwiftUI

struct FinishedResponseView: View {
    let entry: CommandEntry
    let onRerun: () -> Void
    let onEdit: (String) -> Void

    @State private var rendered: RenderedOutput?
    @State private var isShowingAll = false

    var body: some View {
        let rendered = rendered ?? RenderCache.shared.immediate(for: entry)
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            if entry.kind == .interactive {
                InteractiveSummary(entry: entry)
            }
            if let rendered, !rendered.isEmpty {
                OutputBubble(output: rendered.preview, plainText: rendered.plainText, monospaced: rendered.isTabular) {
                    if rendered.isClipped {
                        Button("Mostrar las \(rendered.totalLines) líneas") {
                            isShowingAll = true
                        }
                        .buttonStyle(.link)
                    }
                }
                .contextMenu {
                    Button("Copiar salida", systemImage: "doc.on.doc") { Pasteboard.copy(rendered.plainText) }
                    Button("Copiar comando", systemImage: "terminal") { Pasteboard.copy(entry.command) }
                    Button("Mostrar toda la salida", systemImage: "arrow.up.left.and.arrow.down.right") { isShowingAll = true }
                    Divider()
                    Button("Volver a ejecutar", systemImage: "arrow.clockwise", action: onRerun)
                }
            }
            ReceiptView(entry: entry)
            if let message = entry.hintMessage {
                HintView(message: message, suggestion: entry.hintSuggestion, onUseSuggestion: onEdit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: entry.finishedAt) {
            guard RenderCache.shared[entry] == nil else { return }
            let output = entry.output
            let result = await RenderCache.render(output)
            RenderCache.shared[entry] = result
            self.rendered = result
        }
        #if DEBUG
        .onDebugAction("#showall") { id in
            if id == entry.id.uuidString { isShowingAll = true }
        }
        #endif
        .sheet(isPresented: $isShowingAll) {
            FullOutputSheet(command: entry.command, output: entry.output, lineCount: rendered?.totalLines ?? 0)
        }
    }
}
