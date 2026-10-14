#if DEBUG
import AppKit
import SwiftUI

/// Debug-only scripted runs used to verify the UI without manual input.
///
///     NATIVETERM_SCRIPT     commands separated by `;;`
///     NATIVETERM_SNAPSHOTS  folder where window snapshots are written
///     NATIVETERM_STORE      name of a separate SwiftData store
///     NATIVETERM_APPEARANCE `dark` or `light`
enum DebugAutomation {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var storeName: String? { environment["NATIVETERM_STORE"] }

    static func start(controller: TerminalController) {
        if let appearance = environment["NATIVETERM_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        guard let script = environment["NATIVETERM_SCRIPT"] else { return }
        let commands = script.components(separatedBy: ";;").map { $0.trimmingCharacters(in: .whitespaces) }
        let folder = environment["NATIVETERM_SNAPSHOTS"].map { URL(filePath: $0, directoryHint: .isDirectory) }

        Task {
            try? await Task.sleep(for: .seconds(2))
            for (index, command) in commands.enumerated() {
                if command.hasPrefix("#snap") {
                    snapshot(to: folder, name: String(format: "%02d", index))
                    continue
                }
                if command.hasPrefix("#sleep ") {
                    let seconds = Double(command.dropFirst(7)) ?? 1
                    try? await Task.sleep(for: .seconds(seconds))
                    continue
                }
                if command.hasPrefix("#type ") {
                    NotificationCenter.default.post(name: .debugTypeDraft, object: String(command.dropFirst(6)))
                    continue
                }
                if command == "#interrupt" {
                    controller.selectedShell?.interrupt()
                    continue
                }
                if command.hasPrefix("#send ") {
                    controller.selectedShell?.sendRaw(Array(command.dropFirst(6).replacing("\\r", with: "\r").utf8))
                    continue
                }
                if command == "#new" {
                    controller.createSession()
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                guard let session = controller.selectedSession else { continue }
                let shell = controller.shell(for: session)
                for _ in 0..<600 where shell.phase != .idle {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                controller.submit(command, in: session)
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    @MainActor
    static func snapshot(to folder: URL?, name: String) {
        guard let folder, let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview else { return }
        let bounds = view.bounds
        guard let representation = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: representation)
        let data = representation.representation(using: .png, properties: [:])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data?.write(to: folder.appending(path: "\(name).png"))
    }
}

extension Notification.Name {
    static let debugTypeDraft = Notification.Name("NativeTerminalDebugTypeDraft")
}
#endif
