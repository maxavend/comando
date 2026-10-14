import AppKit
import SwiftData
import SwiftUI

@main
struct NativeTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller: TerminalController
    private let container: ModelContainer

    init() {
        let container = Self.makeContainer()
        let controller = TerminalController(modelContext: container.mainContext)
        self.container = container
        _controller = State(initialValue: controller)
        AppDelegate.controller = controller
    }

    var body: some Scene {
        Window("NativeTerminal", id: "main") {
            RootView()
                .environment(controller)
        }
        .modelContainer(container)
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(controller: controller)
        }

        Settings {
            SettingsView()
        }
    }

    private static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration("NativeTerminal")
        do {
            return try ModelContainer(for: TerminalSession.self, CommandEntry.self, configurations: configuration)
        } catch {
            fatalError("No se pudo abrir la base de datos: \(error)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var controller: TerminalController?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = Self.controller, controller.hasRunningCommands else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "¿Salir de NativeTerminal?")
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
