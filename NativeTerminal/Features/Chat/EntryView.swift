import AppKit
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
        VStack(spacing: 6) {
            if showsTimestamp {
                TimestampSeparator(date: entry.startedAt)
            }
            if showsDirectory {
                DirectoryChip(directory: entry.directory)
            }
            CommandBubble(command: entry.command)
                .contextMenu { commandMenu }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 80)

            if let shell, let live, live.entryID == entry.id {
                LiveResponseView(live: live, shell: shell)
            } else {
                FinishedResponseView(entry: entry, onRerun: { controller.rerun(entry) })
            }
        }
        .padding(.top, 10)
        .padding(.vertical, isHighlighted ? 4 : 0)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.quaternary)
                    .padding(.horizontal, -8)
            }
        }
    }

    @ViewBuilder
    private var commandMenu: some View {
        Button("Copiar comando", systemImage: "doc.on.doc") {
            Pasteboard.copy(entry.command)
        }
        Button("Editar y volver a enviar", systemImage: "pencil") {
            onEdit(entry.command)
        }
        Button("Volver a ejecutar", systemImage: "arrow.clockwise") {
            controller.rerun(entry)
        }
        .disabled(shell?.isBusy ?? false)
    }

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
