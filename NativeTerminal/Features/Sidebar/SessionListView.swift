import SwiftUI

struct SessionListView: View {
    let sessions: [TerminalSession]

    @Environment(TerminalController.self) private var controller
    @State private var renaming: TerminalSession?
    @State private var newName = ""
    @State private var deleting: TerminalSession?

    var body: some View {
        @Bindable var controller = controller
        let shells = controller.shells

        List(selection: $controller.selectedSessionID) {
            ForEach(sessions) { session in
                SessionRow(session: session, isRunning: shells[session.id]?.isBusy ?? false)
                    .tag(session.id)
                    .contextMenu {
                        contextMenu(for: session)
                    }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button("Nueva sesión", systemImage: "square.and.pencil") {
                    controller.createSession()
                }
                .help("Nueva sesión (⌘T)")
            }
        }
        .alert("Renombrar sesión", isPresented: isRenaming, presenting: renaming) { session in
            TextField("Nombre", text: $newName)
            Button("Renombrar") {
                controller.rename(session, to: newName)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Déjalo vacío para usar el nombre de la carpeta.")
        }
        .confirmationDialog(
            "¿Eliminar esta sesión?",
            isPresented: isDeleting,
            presenting: deleting
        ) { session in
            Button("Eliminar sesión", role: .destructive) {
                controller.delete(session)
            }
        } message: { _ in
            Text("Se cerrará su shell y se borrará su historial. Esta acción no se puede deshacer.")
        }
    }

    @ViewBuilder
    private func contextMenu(for session: TerminalSession) -> some View {
        Button("Renombrar…", systemImage: "pencil") {
            newName = session.customName ?? ""
            renaming = session
        }
        Button("Nueva sesión en esta carpeta", systemImage: "plus.square.on.square") {
            controller.createSession(directory: controller.shells[session.id]?.directory ?? session.directory)
        }
        Button("Mostrar en Finder", systemImage: "folder") {
            NSWorkspace.shared.open(URL(filePath: session.directory, directoryHint: .isDirectory))
        }
        Divider()
        Button("Limpiar historial", systemImage: "clear") {
            controller.clearHistory(of: session)
        }
        Button("Eliminar sesión…", systemImage: "trash", role: .destructive) {
            deleting = session
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

private struct SessionRow: View {
    let session: TerminalSession
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            SessionAvatar(isRunning: isRunning)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("En ejecución")
                    } else {
                        Text(Self.timestamp(for: session.lastActivity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(session.lastCommand ?? ShellEscape.abbreviate(session.directory))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .badge(session.unreadCount)
        .help(ShellEscape.abbreviate(session.directory))
        .accessibilityElement(children: .combine)
    }

    /// Messages-style timestamps: time today, “Ayer”, then the date.
    static func timestamp(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Ayer")
        }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

private struct SessionAvatar: View {
    let isRunning: Bool

    var body: some View {
        Image(systemName: "apple.terminal.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [Color(white: 0.62), Color(white: 0.45)], startPoint: .top, endPoint: .bottom),
                in: .circle
            )
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
    }
}
