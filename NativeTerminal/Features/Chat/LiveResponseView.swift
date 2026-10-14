import AppKit
import SwiftTerm
import SwiftUI

/// The reply bubble while a command is still running.
struct LiveResponseView: View {
    let live: LiveOutput
    let shell: ShellSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if live.isInteractive {
                InteractiveTerminalCard(live: live, shell: shell)
            } else if live.hasOutput {
                LiveOutputBubble(live: live)
            } else {
                TypingIndicator()
            }
            RunningFooter(live: live, shell: shell)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveOutputBubble: View {
    let live: LiveOutput

    var body: some View {
        // Reading `version` subscribes this view to throttled buffer updates.
        let _ = live.version
        let rendered = OutputRenderer.renderTail(live.buffer)
        OutputBubble(output: rendered.preview, plainText: rendered.plainText)
    }
}

/// The animated “…” bubble from Messages, shown until the first output arrives.
private struct TypingIndicator: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title2)
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous))
            .frame(width: 52, height: 34)
            .background(.fill.secondary, in: .rect(cornerRadius: 17))
            .accessibilityLabel("Ejecutando")
    }
}

private struct RunningFooter: View {
    let live: LiveOutput
    let shell: ShellSession

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: live.startedAt, by: 1)) { context in
                let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(live.startedAt)))
                Label {
                    Text(elapsed.formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                } icon: {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Detener", systemImage: "stop.fill") {
                shell.interrupt()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Interrumpir el comando (⌘.)")

            if !live.isInteractive {
                Button("Abrir como terminal", systemImage: "macwindow") {
                    shell.openInTerminal()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Muestra este programa en una terminal completa")
            }
        }
        .padding(.leading, 6)
    }
}

// MARK: - Embedded terminal

/// A full terminal for programs that take over the screen (vim, top, less) or
/// need raw keyboard input (ssh, REPLs).
private struct InteractiveTerminalCard: View {
    let live: LiveOutput
    let shell: ShellSession

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(live.command, systemImage: "rectangle.inset.filled.and.cursorarrow")
                    .font(.callout.monospaced())
                    .lineLimit(1)
                Spacer()
                Text("El teclado va directo al programa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            EmbeddedTerminal(shell: shell, fontSize: fontSize)
                .frame(height: 440)
        }
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 14))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator)
        }
    }
}

private struct EmbeddedTerminal: NSViewRepresentable {
    let shell: ShellSession
    let fontSize: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(shell: shell)
    }

    func makeNSView(context: Context) -> TerminalView {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 440), font: font)
        view.configureNativeColors()
        view.optionAsMetaKey = false
        view.terminalDelegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {}

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, @MainActor TerminalViewDelegate {
        let shell: ShellSession
        private weak var view: TerminalView?

        init(shell: ShellSession) {
            self.shell = shell
        }

        func attach(to view: TerminalView) {
            self.view = view
            shell.transcriptProvider = { [weak view] in
                guard let view else { return nil }
                return String(decoding: view.getTerminal().getBufferAsData(kind: .normal), as: UTF8.self)
            }
            shell.attachInteractiveSink { [weak view] bytes in
                view?.feed(byteArray: bytes)
            }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                view.window?.makeFirstResponder(view)
                let terminal = view.getTerminal()
                self.shell.applyWindowSize(columns: terminal.cols, rows: terminal.rows)
            }
        }

        func detach() {
            shell.detachInteractiveSink()
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            shell.applyWindowSize(columns: newCols, rows: newRows)
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            shell.sendRaw(data)
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                Pasteboard.copy(string)
            }
        }

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        }

        func bell(source: TerminalView) {
            NSSound.beep()
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

// MARK: - Full output

/// Shows very long output in a native text view, which handles large text far
/// better than a SwiftUI `Text`.
struct FullOutputSheet: View {
    let command: String
    let output: Data

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        NavigationStack {
            OutputTextView(output: output, fontSize: fontSize)
                .navigationTitle(command)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Copiar todo", systemImage: "doc.on.doc") {
                            Pasteboard.copy(OutputRenderer.plainText(raw: [UInt8](output)))
                        }
                    }
                }
        }
        .frame(minWidth: 640, idealWidth: 860, minHeight: 420, idealHeight: 640)
    }
}

private struct OutputTextView: NSViewRepresentable {
    let output: Data
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 12, height: 12)
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.textStorage?.setAttributedString(
                OutputRenderer.fullAttributedString(raw: [UInt8](output), font: font)
            )
        }
        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {}
}
