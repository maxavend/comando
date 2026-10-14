import SwiftUI

/// One exchange in the chat: the command bubble and the shell's reply.
struct EntryView: View {
    let entry: CommandEntry
    let previous: CommandEntry?
    let shell: ShellSession?
    let isHighlighted: Bool
    let onEdit: (String) -> Void

    @Environment(TerminalController.self) private var controller

    var body: some View {
        let live = shell?.live
        VStack(spacing: Metrics.replySpacing) {
            if showsTimestamp || showsDirectory {
                ExchangeHeader(
                    date: showsTimestamp ? entry.startedAt : nil,
                    directory: showsDirectory ? entry.directory : nil
                )
            }
            CommandBubble(command: entry.command)
                .contextMenu { commandMenu }
                .padding(.leading, Metrics.bubbleOppositeInset)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let shell, let live, live.entryID == entry.id {
                LiveResponseView(live: live, shell: shell)
            } else {
                FinishedResponseView(entry: entry, onRerun: rerun)
            }
        }
        .padding(.top, Metrics.exchangeSpacing)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .fill(.tint.quaternary)
                .padding(.horizontal, -Metrics.bubbleHorizontalPadding / 2)
                .padding(.top, Metrics.exchangeSpacing / 2)
                .padding(.bottom, -Metrics.exchangeSpacing / 2)
                .opacity(isHighlighted ? 1 : 0)
        }
    }

    @ViewBuilder
    private var commandMenu: some View {
        Button("Copiar comando", systemImage: "doc.on.doc", action: copyCommand)
        Button("Editar y volver a enviar", systemImage: "pencil", action: edit)
        Button("Volver a ejecutar", systemImage: "arrow.clockwise", action: rerun)
            .disabled(shell?.isBusy ?? false)
    }

    private func copyCommand() { Pasteboard.copy(entry.command) }
    private func edit() { onEdit(entry.command) }
    private func rerun() { controller.rerun(entry) }

    /// Like Messages: a timestamp when there's a pause of more than 15 minutes.
    private var showsTimestamp: Bool {
        guard let previous else { return true }
        return entry.startedAt.timeIntervalSince(previous.startedAt) > 15 * 60
    }

    private var showsDirectory: Bool {
        guard let previous else { return true }
        return previous.directory != entry.directory
    }
}
