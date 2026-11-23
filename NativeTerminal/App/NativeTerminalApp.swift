import AppKit
import Observation
import SwiftData
import SwiftUI

@main
struct NativeTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller: TerminalController
    private let container: ModelContainer

    init() {
        // Launched from the shell as one of its built-in commands: do that and quit.
        if let code = BuiltInTools.runIfRequested() { exit(code) }
        let container = Self.makeContainer()
        let controller = TerminalController(modelContext: container.mainContext)
        self.container = container
        _controller = State(initialValue: controller)
        AppDelegate.controller = controller
    }

    var body: some Scene {
        Window("Comando", id: "main") {
            RootView { action in
                appDelegate.openMainWindow = { action(id: "main") }
            }
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
            return try ModelContainer(for: TerminalSession.self, CommandEntry.self, SavedRecipe.self, configurations: configuration)
        } catch {
            fatalError("No se pudo abrir la base de datos: \(error)")
        }
    }
}


/// The status item belongs to AppKit so it doesn't participate in SwiftUI's
/// window restoration or change which window opens when launching Comando.
final class ActivityStatusItem: NSObject {
    private let controller: TerminalController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let openMainWindow: () -> Void

    init(controller: TerminalController, openMainWindow: @escaping () -> Void) {
        self.controller = controller
        self.openMainWindow = openMainWindow
        super.init()
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.imagePosition = .imageLeading
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ActivityMenu(
            controller: controller,
            onOpen: { [weak self] in self?.showWindow(sessionID: $0) },
            onQuit: { [weak self] in
                self?.popover.close()
                NSApp.terminate(nil)
            }
        ))
        updateIndicator()
        #if DEBUG
        NotificationCenter.default.addObserver(forName: .debugAction, object: nil, queue: .main) { [weak self] note in
            guard note.object as? String == "#menubar" else { return }
            MainActor.assumeIsolated { self?.togglePopover() }
        }
        #endif
    }

    private func updateIndicator() {
        let count = withObservationTracking {
            ActiveSession.count(in: controller)
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIndicator() }
        }
        let label = count == 0 ? String(localized: "Comando") : String(localized: "Comando · Sesiones activas: \(count)")
        item.button?.image = NSImage(named: "MenuBarComando")
        item.button?.title = count == 0 ? "" : count.formatted()
        item.button?.setAccessibilityLabel(label)
        item.button?.toolTip = label
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showWindow(sessionID: UUID?) {
        popover.close()
        if let sessionID, controller.session(withID: sessionID) != nil {
            controller.selectedSessionID = sessionID
            controller.activityNavigationRequest += 1
        }
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        openMainWindow()
        NSApp.activate()
    }
}

private struct ActiveSession: Identifiable {
    let id: UUID
    let name: String
    let command: String
    let startedAt: Date?

    static func count(in controller: TerminalController) -> Int {
        activeIDs(in: controller).count
    }

    static func rows(in controller: TerminalController) -> [Self] {
        activeIDs(in: controller).compactMap { id -> Self? in
            guard let session = controller.session(withID: id) else { return nil }
            let shell = controller.shells[id]
            let agent = controller.agentChats[id]
            let live = shell?.isBusy == true ? shell?.live : nil
            if let live, shell?.phase == .interactive || agent?.isResponding != true {
                return Self(id: id, name: session.displayName, command: live.command, startedAt: live.startedAt)
            }
            if let agent, agent.isResponding {
                return Self(id: id, name: session.displayName, command: agent.kind.displayName,
                            startedAt: agent.activeTurnStartedAt)
            }
            return Self(id: id, name: session.displayName, command: session.lastCommand ?? String(localized: "Terminal"),
                        startedAt: nil)
        }
        .sorted { ($0.startedAt ?? .distantFuture, $0.id.uuidString) < ($1.startedAt ?? .distantFuture, $1.id.uuidString) }
    }

    private static func activeIDs(in controller: TerminalController) -> Set<UUID> {
        Set(controller.shells.values.lazy.filter(\.isBusy).map(\.id))
            .union(controller.agentChats.values.lazy.filter(\.isResponding).map(\.sessionID))
    }
}

private struct ActivityMenu: View {
    let controller: TerminalController
    let onOpen: (UUID?) -> Void
    let onQuit: () -> Void

    var body: some View {
        let rows = ActiveSession.rows(in: controller)
        VStack(alignment: .leading, spacing: 12) {
            header(count: rows.count)
            if rows.isEmpty {
                Text("Sin sesiones en ejecución")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if rows.count <= 4 {
                sessionList(rows)
            } else {
                ScrollView { sessionList(rows) }
                    .frame(height: 228)
            }
            Divider()
            HStack {
                Button { onOpen(nil) } label: {
                    Label("Abrir Comando", systemImage: "macwindow")
                }
                Spacer()
                Button("Salir de Comando", action: onQuit)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 340)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 9) {
            Image("MenuBarComando")
                .renderingMode(.template)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("Comando")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if count > 0 {
                Label(count == 1 ? String(localized: "1 sesión activa") : String(localized: "\(count) sesiones activas"),
                      systemImage: "circle.fill")
                    .font(.caption.weight(.medium))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func sessionList(_ rows: [ActiveSession]) -> some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                Button { onOpen(row.id) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(row.command)
                                .font(.system(.callout, design: .monospaced).weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        if let start = row.startedAt {
                            Text(start, style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(Text("Tiempo en ejecución: \(Text(start, style: .timer))"))
                        }
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(10)
                    .contentShape(.rect)
                }
                .buttonStyle(ActivityRowStyle())
                .help(row.command)
                .accessibilityIdentifier("activeSession")
            }
        }
    }
}

private struct ActivityRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isHovered || configuration.isPressed ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary),
                        in: .rect(cornerRadius: 8))
            .onHover { isHovered = $0 }
    }
}
