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
        Window("Comando", id: "main") {
            RootView()
                .environment(controller)
        }
        .modelContainer(container)
        .defaultSize(width: 980, height: 680)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(controller: controller)
        }

        Window("Herramientas", id: "tools") {
            ToolsView()
                .environment(controller)
        }
        .defaultSize(width: 1120, height: 640)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }

    private static func makeContainer() -> ModelContainer {
        // The store keeps its first name so history survives the rename.
        var name = "NativeTerminal"
        #if DEBUG
        if let debugName = DebugAutomation.storeName { name = debugName }
        #endif
        let configuration = ModelConfiguration(name)
        do {
            return try ModelContainer(for: TerminalSession.self, CommandEntry.self, configurations: configuration)
        } catch {
            fatalError("No se pudo abrir la base de datos: \(error)")
        }
    }
}
