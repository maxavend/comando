#if DEBUG
import AppKit
import SwiftData
import SwiftUI

/// Debug-only scripted runs used to verify the UI without manual input.
///
///     NATIVETERM_SCRIPT     steps separated by `;;` (shell commands or `#` actions)
///     NATIVETERM_SNAPSHOTS  folder used to request screenshots from an outside watcher
///     NATIVETERM_STORE      name of a separate SwiftData store
///     NATIVETERM_APPEARANCE `dark` or `light`
///
/// `#snap name` writes `name.request` and waits until the watcher deletes it.
enum DebugAutomation {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var storeName: String? { environment["NATIVETERM_STORE"] }

    static func start(controller: TerminalController) {
        if let appearance = environment["NATIVETERM_APPEARANCE"] {
            setAppearance(appearance)
        }
        guard let script = environment["NATIVETERM_SCRIPT"] else { return }
        let steps = script.components(separatedBy: ";;").map { $0.trimmingCharacters(in: .whitespaces) }
        let folder = environment["NATIVETERM_SNAPSHOTS"].map { URL(filePath: $0, directoryHint: .isDirectory) }

        Task {
            try? await Task.sleep(for: .seconds(2))
            for step in steps {
                await run(step, controller: controller, folder: folder)
            }
            if let folder {
                try? Data().write(to: folder.appending(path: "done"))
            }
        }
    }

    private static func run(_ step: String, controller: TerminalController, folder: URL?) async {
        let (action, argument) = split(step)
        switch action {
        case "#snap":
            await requestSnapshot(named: argument, in: folder)
        case "#sleep":
            try? await Task.sleep(for: .seconds(Double(argument) ?? 1))
        case "#ask":
            if let session = controller.selectedSession {
                let files = environment["NATIVETERM_ATTACH"].flatMap { $0.isEmpty ? nil : [URL(filePath: $0)] } ?? []
                controller.ask(argument, attachments: ["audio", "documento", "esto"].contains(where: argument.contains) ? files : [], in: session)
                try? await Task.sleep(for: .milliseconds(300))
            }
        case "#axdump":
            // Walks the accessibility tree like UI tests do, to catch crashes there.
            var lines: [String] = []
            let out = (folder?.path(percentEncoded: false) ?? NSTemporaryDirectory()) + "/ax.txt"
            func value(_ element: NSObject, _ attribute: NSAccessibility.Attribute) -> Any? {
                element.accessibilityAttributeValue(attribute)
            }
            func walk(_ element: NSObject, depth: Int) {
                guard depth < 80 else { return }
                let role = value(element, .role) as? String ?? "?"
                lines.append(String(repeating: " ", count: depth) + role + " …")
                try? lines.joined(separator: "\n").write(toFile: out, atomically: false, encoding: .utf8)
                let label = [value(element, .title), value(element, .description), value(element, .value)]
                    .compactMap { $0.map { "\($0)" } }.joined(separator: " | ")
                lines[lines.count - 1] = String(repeating: " ", count: depth) + role + " «" + label.prefix(80) + "»"
                for child in value(element, .children) as? [NSObject] ?? [] { walk(child, depth: depth + 1) }
            }
            for window in NSApp.windows where window.isVisible { walk(window, depth: 0) }
            try? lines.joined(separator: "\n").write(toFile: out, atomically: false, encoding: .utf8)
        case "#pin":
            controller.selectedSession?.isPinned = true
        case "#style":
            let parts = argument.split(separator: " ")
            controller.selectedSession?.emoji = parts.first.map(String.init)
            controller.selectedSession?.colorIndex = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        case "#explain":
            NotificationCenter.default.post(name: .debugAction, object: "#explain \(lastEntryID(controller)?.uuidString ?? "")")
            try? await Task.sleep(for: .milliseconds(800))
        case "#recipes":
            controller.isShowingRecipes = true
            try? await Task.sleep(for: .seconds(1))
        case "#welcome":
            controller.isShowingWelcome = true
            try? await Task.sleep(for: .seconds(1))
        case "#type", "#submit", "#rename", "#delete", "#search", "#scope", "#showall", "#tab", "#next", "#query", "#choose", "#attach", "#tools", "#toolsection", "#toolselect":
            var object = argument
            if action == "#showall" { object = lastEntryID(controller)?.uuidString ?? "" }
            NotificationCenter.default.post(name: .debugAction, object: "\(action) \(object)")
            try? await Task.sleep(for: .milliseconds(600))
        case "#interrupt":
            controller.selectedShell?.interrupt()
        case "#send":
            controller.selectedShell?.sendRaw(Array(argument.replacing("\\r", with: "\r").utf8))
        case "#agentterminal":
            if let session = controller.selectedSession { controller.openAgentInTerminal(in: session) }
        case "#agentchat":
            if let session = controller.selectedSession { controller.returnToAgentChat(in: session) }
        case "#allow":
            if let session = controller.selectedSession {
                controller.allowAgent(argument == "all" ? .all : .edits, in: session)
            }
        case "#new":
            controller.createSession(directory: argument.isEmpty ? nil : ShellEscape.expandTilde(argument))
            try? await Task.sleep(for: .seconds(1))
        case "#select":
            controller.selectAdjacentSession(offset: Int(argument) ?? 1)
            try? await Task.sleep(for: .milliseconds(500))
        case "#settings":
            NotificationCenter.default.post(name: .debugAction, object: "#settings")
            try? await Task.sleep(for: .seconds(1))
        case "#close":
            // SwiftUI sheets dismiss themselves; only close AppKit windows if one remains.
            NotificationCenter.default.post(name: .debugAction, object: "#close")
            try? await Task.sleep(for: .milliseconds(500))
            if mainWindow?.attachedSheet == nil { closeTopmost() }
            try? await Task.sleep(for: .milliseconds(600))
        case "#appearance":
            setAppearance(argument)
            try? await Task.sleep(for: .milliseconds(500))
        case "#size":
            let parts = argument.split(separator: " ").compactMap { Double($0) }
            if parts.count == 2, let window = mainWindow {
                var frame = window.frame
                frame.origin.y += frame.height - parts[1]
                frame.size = CGSize(width: parts[0], height: parts[1])
                window.setFrame(frame, display: true)
            }
            try? await Task.sleep(for: .milliseconds(500))
        default:
            guard let session = controller.selectedSession else { return }
            let shell = controller.shell(for: session)
            for _ in 0..<600 where shell.phase != .idle {
                try? await Task.sleep(for: .milliseconds(100))
            }
            controller.submit(step, in: session)
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    private static func split(_ step: String) -> (String, String) {
        guard step.hasPrefix("#") else { return (step, "") }
        let parts = step.split(separator: " ", maxSplits: 1)
        return (String(parts[0]), parts.count > 1 ? String(parts[1]) : "")
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    private static func setAppearance(_ name: String) {
        NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
    }

    private static func closeTopmost() {
        if let window = mainWindow, let sheet = window.attachedSheet {
            window.endSheet(sheet)
        } else if let key = NSApp.keyWindow, key != mainWindow {
            key.close()
        }
    }

    private static func lastEntryID(_ controller: TerminalController) -> UUID? {
        controller.selectedSession?.entries.max { $0.startedAt < $1.startedAt }?.id
    }

    /// Writes the window frame (in screen points, top-left origin) and waits for
    /// the outside watcher to capture it.
    private static func requestSnapshot(named name: String, in folder: URL?) async {
        guard let folder, let window = mainWindow, let screen = window.screen ?? NSScreen.main else { return }
        try? await Task.sleep(for: .milliseconds(700))
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let frame = window.frame
        let rect = "\(Int(frame.minX)),\(Int(mainHeight - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))"
        let request = folder.appending(path: "\(name).request")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? rect.write(to: request, atomically: true, encoding: .utf8)
        for _ in 0..<100 where FileManager.default.fileExists(atPath: request.path(percentEncoded: false)) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

extension Notification.Name {
    static let debugAction = Notification.Name("NativeTerminalDebugAction")
}

extension View {
    /// Runs `handler` with the argument of debug actions named `action`.
    func onDebugAction(_ action: String, perform handler: @escaping (String) -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .debugAction)) { note in
            guard let text = note.object as? String, text == action || text.hasPrefix(action + " ") else { return }
            handler(String(text.dropFirst(action.count)).trimmingCharacters(in: .whitespaces))
        }
    }
}
#endif
