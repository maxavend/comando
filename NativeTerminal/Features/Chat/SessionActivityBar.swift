import SwiftUI

/// What's open in this session, under the header when its card is out of
/// view: an agent conversation or a program with its own screen. It matches the avatar's
/// green dot, with a way to see it and to close it.
struct SessionActivityBar: View {
    let session: TerminalSession
    let shell: ShellSession?

    @Environment(TerminalController.self) private var controller

    var body: some View {
        if let activity {
            HStack(spacing: Metrics.chipSpacing) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(activity.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Button(activity.showTitle, systemImage: "macwindow", action: activity.show)
                Button("Terminar", systemImage: "xmark", action: activity.close)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .padding(.leading, Metrics.bubbleHorizontalPadding)
            .padding(.trailing, Metrics.statusSpacing)
            .padding(.vertical, Metrics.statusSpacing)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }

    private struct Activity {
        var title: String
        var showTitle: LocalizedStringKey
        var show: () -> Void
        var close: () -> Void
    }

    private var activity: Activity? {
        if let shell, shell.phase == .interactive, let live = shell.live {
            let program = ShellSession.firstWord(of: live.command)
            let entryID = live.entryID
            return Activity(
                title: String(localized: "\(program) en ejecución"),
                showTitle: "Ver",
                show: { controller.focusedEntryID = entryID },
                close: { shell.quitForeground() }
            )
        }
        if let chat = controller.agentChats[session.id], !(shell?.isBusy ?? false) {
            return Activity(
                title: chat.isReady
                    ? String(localized: "\(chat.kind.displayName) en línea")
                    : String(localized: "Iniciando \(chat.kind.displayName)…"),
                showTitle: "Ver en la terminal",
                show: { controller.openAgentInTerminal(in: session) },
                close: { controller.endAgent(in: session) }
            )
        }
        return nil
    }
}
