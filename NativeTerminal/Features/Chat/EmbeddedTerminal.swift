import AppKit
import SwiftTerm
import SwiftUI

struct EmbeddedTerminal: NSViewRepresentable {
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
            // Wait for the view to join the window before focusing and sizing it.
            Task { [weak self, weak view] in
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
