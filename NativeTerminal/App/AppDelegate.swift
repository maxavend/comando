import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var controller: TerminalController?
    var openMainWindow: (() -> Void)?
    private var activityStatusItem: ActivityStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let controller = Self.controller {
            activityStatusItem = ActivityStatusItem(controller: controller) { [weak self] in
                self?.openMainWindow?()
            }
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
        center.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, Self.isContentWindow(closing) else { return }
        let otherWindowIsOpen = NSApp.windows.contains {
            $0 !== closing && Self.isContentWindow($0) && ($0.isVisible || $0.isMiniaturized)
        }
        if !otherWindowIsOpen {
            // Wait for AppKit to finish closing or it may reactivate the app.
            DispatchQueue.main.async {
                guard !NSApp.windows.contains(where: {
                    Self.isContentWindow($0) && ($0.isVisible || $0.isMiniaturized)
                }) else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isContentWindow(window),
              NSApp.activationPolicy() == .accessory else { return }
        NSApp.setActivationPolicy(.regular)
    }

    private static func isContentWindow(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = Self.controller, controller.hasRunningCommands else { return .terminateNow }
        sender.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "¿Salir de Comando?")
        alert.informativeText = String(localized: "Hay comandos o agentes en ejecución. Si sales, se detendrán.")
        alert.addButton(withTitle: String(localized: "Salir"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.controller?.terminateAll()
    }
}
