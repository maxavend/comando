import SwiftUI

struct AppCommands: Commands {
    let controller: TerminalController

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nueva sesión") {
                controller.createSession()
            }
            .keyboardShortcut("t")

            Button("Nueva sesión en la misma carpeta") {
                controller.createSession(directory: controller.selectedShellDirectory)
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
        }

        CommandGroup(replacing: .help) {
            Button("Bienvenida a Comando") {
                controller.isShowingWelcome = true
            }
        }

        CommandGroup(after: .newItem) {
            Button("Recetas…") {
                controller.isShowingRecipes = true
            }
            .keyboardShortcut("k")

            Button("Herramientas instaladas…") {
                openWindow(id: "tools")
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu("Ir") {
            Group {
                Button("Subir un nivel") { withSession { controller.navigateUp(in: $0) } }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Divider()
                Button("Inicio") { go(to: NSHomeDirectory()) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Escritorio") { go(to: NSHomeDirectory() + "/Desktop") }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Documentos") { go(to: NSHomeDirectory() + "/Documents") }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Descargas") { go(to: NSHomeDirectory() + "/Downloads") }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Ir a una carpeta…") { controller.isPickingFolder = true }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            .disabled(controller.selectedShell?.isBusy ?? false)
        }

        CommandMenu("Shell") {
            Button("Detener comando") {
                controller.selectedShell?.interrupt()
            }
            .keyboardShortcut(".")
            .disabled(!(controller.selectedShell?.isBusy ?? false))

            Button("Enviar fin de entrada (EOF)") {
                controller.selectedShell?.sendEOF()
            }
            .disabled(!(controller.selectedShell?.isBusy ?? false))

            Button("Abrir como terminal") {
                controller.selectedShell?.openInTerminal()
            }
            .disabled(controller.selectedShell?.phase != .running)

            Divider()

            Button("Limpiar historial") {
                if let session = controller.selectedSession {
                    controller.clearHistory(of: session)
                }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Reiniciar shell") {
                if let session = controller.selectedSession {
                    controller.restartShell(of: session)
                }
            }

            Divider()

            Button("Sesión siguiente") {
                controller.selectAdjacentSession(offset: 1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Sesión anterior") {
                controller.selectAdjacentSession(offset: -1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }

    private func withSession(_ action: (TerminalSession) -> Void) {
        if let session = controller.selectedSession { action(session) }
    }

    private func go(to folder: String) {
        withSession { controller.navigate(to: folder, in: $0) }
    }
}
