import SwiftUI

/// One exchange in the chat: the command bubble and the shell's reply.
struct EntryView: View {
    let entry: CommandEntry
    let previous: CommandEntry?
    let shell: ShellSession?
    let isHighlighted: Bool
    let onEdit: (String) -> Void

    @Environment(TerminalController.self) private var controller
    @State private var isExplaining = false

    var body: some View {
        let live = shell?.live
        VStack(spacing: Metrics.replySpacing) {
            if showsTimestamp || showsDirectory {
                ExchangeHeader(
                    date: showsTimestamp ? entry.startedAt : nil,
                    directory: showsDirectory ? entry.directory : nil
                )
            }
            if entry.kind == .assistant {
                AssistantExchangeView(entry: entry, shell: shell, onEdit: onEdit)
            } else {
                commandExchange(live: live)
            }
        }
        .padding(.top, Metrics.exchangeSpacing)
        #if DEBUG
        .onDebugAction("#explain") { id in
            if id == entry.id.uuidString { isExplaining = true }
        }
        #endif
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
    private func commandExchange(live: LiveOutput?) -> some View {
        VStack(alignment: .trailing, spacing: Metrics.statusSpacing) {
            CommandBubble(command: entry.command)
                .contextMenu { commandMenu }
                .popover(isPresented: $isExplaining, arrowEdge: .leading) {
                    CommandBreakdownView(command: entry.command)
                }
            if let description = CommandGlossary.describe(entry.command) {
                CommandDescription(text: description, command: entry.command)
            }
        }
        .padding(.leading, Metrics.bubbleOppositeInset)
        .frame(maxWidth: .infinity, alignment: .trailing)

        if let shell, let live, live.entryID == entry.id {
            LiveResponseView(live: live, shell: shell)
        } else {
            FinishedResponseView(entry: entry, onRerun: rerun, onEdit: onEdit, onOpenFolder: openFolder)
            if let folder = entry.movedTo {
                LocationNotice(folder: folder)
            }
        }
    }

    @ViewBuilder
    private var commandMenu: some View {
        Button("¿Qué hace este comando?", systemImage: "info.circle", action: explain)
        Button("Copiar comando", systemImage: "doc.on.doc", action: copyCommand)
        Button("Editar y volver a enviar", systemImage: "pencil", action: edit)
        Button("Volver a ejecutar", systemImage: "arrow.clockwise", action: rerun)
            .disabled(shell?.isBusy ?? false)
    }

    private func copyCommand() { Pasteboard.copy(entry.command) }
    private func explain() { isExplaining = true }
    private func edit() { onEdit(entry.command) }
    private func rerun() { controller.rerun(entry) }

    private func openFolder(_ path: String) {
        guard let session = entry.session else { return }
        controller.navigate(to: path, in: session)
    }

    /// Like Messages: a timestamp when there's a pause of more than 15 minutes.
    private var showsTimestamp: Bool {
        guard let previous else { return true }
        return entry.startedAt.timeIntervalSince(previous.startedAt) > 15 * 60
    }

    /// Shown when the folder differs from where the previous exchange left off.
    private var showsDirectory: Bool {
        guard let previous else { return true }
        return (previous.endDirectory ?? previous.directory) != entry.directory
    }
}
