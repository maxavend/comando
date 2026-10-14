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
                SessionRow(session: session, shell: shells[session.id])
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
        .alert("Renombrar sesión", item: $renaming) { session in
            TextField("Nombre", text: $newName)
            Button("Renombrar") {
                controller.rename(session, to: newName)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Déjalo vacío para usar el nombre de la carpeta.")
        }
        .confirmationDialog("¿Eliminar esta sesión?", item: $deleting) { session in
            Button("Eliminar sesión", role: .destructive) {
                controller.delete(session)
            }
        } message: { _ in
            Text("Se cerrará su shell y se borrará su historial. Esta acción no se puede deshacer.")
        }
    }

    @ViewBuilder
    private func contextMenu(for session: TerminalSession) -> some View {
        if let shell = controller.shells[session.id], shell.isBusy {
            Button("Detener comando", systemImage: "stop.circle") { shell.interrupt() }
            if let url = shell.live?.localURL {
                Button("Abrir en el navegador", systemImage: "safari") { NSWorkspace.shared.open(url) }
            }
            Divider()
        }
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
}
