import SwiftUI

/// Shown in place of a chat when several sessions are selected in the
/// sidebar, like Mail with several messages: what they are, and what can be
/// done with all of them.
struct MultipleSessionsView: View {
    let sessions: [TerminalSession]

    @Environment(TerminalController.self) private var controller
    @State private var deleting: [TerminalSession] = []

    var body: some View {
        let allArchived = sessions.allSatisfy(\.isArchived)
        VStack(spacing: 18) {
            avatars
            VStack(spacing: 4) {
                Text("^[\(sessions.count) sesión](inflect: true) seleccionadas")
                    .font(.title2.weight(.semibold))
                Text(names)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 10) {
                if allArchived {
                    Button("Desarchivar", systemImage: "tray.and.arrow.up") { controller.unarchive(sessions) }
                } else {
                    Button("Archivar", systemImage: "archivebox") { controller.archive(sessions) }
                        .help("Archivar (⌃⌘A)")
                }
                Button("Eliminar…", systemImage: "trash", role: .destructive) { deleting = sessions }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            Text("⌘-clic o ⇧-clic en la barra lateral para elegir otras.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text("^[\(sessions.count) sesión](inflect: true)"))
        .sessionDeleteConfirmation($deleting)
    }

    /// Up to four avatars, overlapping like a stack.
    private var avatars: some View {
        HStack(spacing: -14) {
            ForEach(sessions.prefix(4)) { session in
                SessionAvatar(isRunning: false, emoji: session.emoji, colorIndex: session.colorIndex,
                              size: 56, symbol: session.avatarSymbol(for: session.directory))
                    .overlay(Circle().stroke(.background, lineWidth: 3))
            }
        }
    }

    private var names: String {
        let shown = sessions.prefix(4).map(\.displayName)
        let rest = sessions.count - shown.count
        let list = shown.formatted(.list(type: .and))
        return rest > 0 ? String(localized: "\(list) y \(rest) más") : list
    }
}
