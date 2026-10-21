import AppKit
import QuickLook
import SwiftUI

struct FinishedResponseView: View {
    let entry: CommandEntry
    let onRerun: () -> Void
    let onEdit: (String) -> Void
    /// Opens a folder from a clicked file name (runs `cd`).
    let onOpenFolder: (String) -> Void

    @State private var rendered: RenderedOutput?
    @State private var isShowingAll = false
    @State private var quickLookURL: URL?
    @State private var startsSearching = false

    var body: some View {
        let rendered = rendered ?? RenderCache.shared.immediate(for: entry)
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            if entry.kind == .interactive {
                InteractiveSummary(entry: entry)
            }
            if let rendered, !rendered.isEmpty {
                OutputBubble(
                    output: rendered.preview,
                    plainText: rendered.plainText,
                    monospaced: rendered.isTabular,
                    lineCount: rendered.previewLines,
                    onShowAll: rendered.isClipped ? { showAll(searching: false) } : nil
                )
                .contextMenu {
                    Button("Copiar salida", systemImage: "doc.on.doc") { Pasteboard.copy(rendered.plainText) }
                    Button("Copiar comando", systemImage: "terminal") { Pasteboard.copy(entry.command) }
                    Button("Mostrar toda la salida", systemImage: "arrow.up.left.and.arrow.down.right") { showAll(searching: false) }
                    Button("Buscar en la salida…", systemImage: "magnifyingglass") { showAll(searching: true) }
                    Divider()
                    Button("Volver a ejecutar", systemImage: "arrow.clockwise", action: onRerun)
                }
            }
            if Self.showsReceipt(for: entry, hasOutput: !(rendered?.isEmpty ?? true)) {
                ReceiptView(entry: entry)
            }
            if let message = entry.hintMessage {
                HintView(message: message, suggestion: entry.hintSuggestion, onUseSuggestion: onEdit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction(handler: open))
        .quickLookPreview($quickLookURL)
        .task(id: entry.finishedAt) {
            guard RenderCache.shared[entry] == nil else { return }
            let output = entry.output
            let result = RenderCache.linked(await RenderCache.render(output), for: entry)
            RenderCache.shared[entry] = result
            self.rendered = result
        }
        #if DEBUG
        .onDebugAction("#showall") { id in
            if id == entry.id.uuidString { isShowingAll = true }
        }
        #endif
        .sheet(isPresented: $isShowingAll) {
            FullOutputSheet(command: entry.command, output: entry.output, lineCount: rendered?.totalLines ?? 0, startsSearching: startsSearching)
        }
    }

    /// Like “Entregado” in Messages, the status line appears only when it
    /// says something: a failure, a stop, a long run, or a quiet success.
    static func showsReceipt(for entry: CommandEntry, hasOutput: Bool) -> Bool {
        if entry.wasInterrupted || entry.wasStopped || entry.truncated { return true }
        if let code = entry.exitCode, code != 0 { return true }
        if let duration = entry.duration, duration >= .seconds(3) { return true }
        // No output and no folder change: “Listo” is the only answer.
        return !hasOutput && entry.movedTo == nil && entry.kind != .interactive
    }

    private func showAll(searching: Bool) {
        startsSearching = searching
        isShowingAll = true
    }

    /// File names in `ls` output: a folder opens in the session, a file shows
    /// in Quick Look, and ⌘-click opens it in its app, like Finder.
    private func open(_ url: URL) -> OpenURLAction.Result {
        guard url.isFileURL else { return .systemAction }
        var isDirectory: ObjCBool = false
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .discarded }
        if isDirectory.boolValue && !path.hasSuffix(".app") {
            onOpenFolder(path)
        } else if NSEvent.modifierFlags.contains(.command) {
            NSWorkspace.shared.open(url)
        } else {
            quickLookURL = url
        }
        return .handled
    }
}
