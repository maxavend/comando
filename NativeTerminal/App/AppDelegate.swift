import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var controller: TerminalController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = Self.controller, controller.hasRunningCommands else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "¿Salir de Comando?")
        alert.informativeText = String(localized: "Hay comandos en ejecución. Si sales, se detendrán.")
        alert.addButton(withTitle: String(localized: "Salir"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.controller?.terminateAll()
    }
}
