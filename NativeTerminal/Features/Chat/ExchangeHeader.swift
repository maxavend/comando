import SwiftUI

/// Centered context above an exchange, like the notes between conversations
/// in Messages: when it happened, after a pause, and which folder the shell is
/// in, when that changed. The folder opens a menu to go somewhere else.
struct ExchangeHeader: View {
    let date: Date?
    let directory: String?
    var session: TerminalSession?

    var body: some View {
        VStack(spacing: Metrics.statusSpacing) {
            if let date {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .fontWeight(.medium)
            }
            if let directory {
                FolderNotice(folder: directory, session: session)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, date != nil ? Metrics.timestampSpacing - Metrics.messageSpacing : 0)
        .padding(.bottom, Metrics.statusSpacing)
    }
}

/// “Estás en tu carpeta personal”, or “Ahora estás en Escritorio” after a
/// `cd`. Pressing it opens a menu to go to another folder or show this one in
/// Finder.
struct FolderNotice: View {
    let folder: String
    var session: TerminalSession?
    /// The shell just moved here.
    var isChange = false

    @Environment(TerminalController.self) private var controller
    @State private var isHovering = false

    var body: some View {
        if let session {
            Menu {
                FolderMenuItems(
                    session: session,
                    directory: controller.shells[session.id]?.directory ?? session.directory,
                    shown: folder
                )
            } label: {
                label(opensMenu: true)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovering = $0 }
            .help("Ir a otra carpeta o mostrar \(ShellEscape.abbreviate(folder)) en Finder")
        } else {
            label(opensMenu: false)
                .help(ShellEscape.abbreviate(folder))
        }
    }

    private func label(opensMenu: Bool) -> some View {
        let name = Text(FolderName.phrase(folder)).fontWeight(.medium)
        return HStack(spacing: Metrics.statusSpacing) {
            Image(systemName: "folder")
            Text(isChange ? "Ahora estás en \(name)" : "Estás en \(name)")
            if opensMenu {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .imageScale(.small)
            }
        }
        .lineLimit(1)
        // A soft capsule on hover says it can be pressed.
        .padding(.horizontal, opensMenu ? 8 : 0)
        .padding(.vertical, opensMenu ? 3 : 0)
        .background(.fill.tertiary.opacity(isHovering ? 1 : 0), in: .capsule)
        .foregroundStyle(isHovering ? .primary : .secondary)
        .contentShape(.capsule)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carpeta \(FolderName.display(folder))")
        .accessibilityHint(opensMenu ? Text("Abre un menú para ir a otra carpeta") : Text(""))
    }
}
