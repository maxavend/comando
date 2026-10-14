import SwiftUI

struct AppCommands: Commands {
    let controller: TerminalController

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
            .keyboardShortcut("k")

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
}
