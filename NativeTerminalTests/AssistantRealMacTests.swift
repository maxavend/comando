import Foundation
import Testing
@testable import NativeTerminal

/// Requests against what is really installed on this Mac. Runs with NATIVETERM_STRESS.
@Suite(.enabled(if: AssistantEngine.isAvailable && ProcessInfo.processInfo.environment["NATIVETERM_STRESS"] != nil))
struct AssistantRealMacTests {
    @Test func realInstalledApps() async {
        let path = (ProcessInfo.processInfo.environment["NATIVETERM_PATH"] ?? "/opt/homebrew/bin:/usr/bin:/bin").split(separator: ":").map(String.init)
        let executables = Set(ExecutableIndex.shared.names(for: path))
        let inventory = await ToolInventory.gather(directory: NSHomeDirectory(), executables: executables, attachments: [], path: path)
        for request in ["Quiero abrir antigravity CLI", "abre antigravity", "abre visual studio code", "abre cursor", "abre claude",
                        "¿tengo docker?", "¿tengo ffmpeg instalado?", "abre la configuración del sistema", "abre el monitor de actividad",
                        "abre xcode", "abre la terminal"] {
            let start = ContinuousClock.now
            let reply = await AssistantEngine.reply(to: request, inventory: inventory)
            print("REAL ⏱ \(ContinuousClock.now - start) «\(request)» → \(reply.error ?? reply.explanation) ⌘ \(reply.proposals.map(\.command))")
        }
    }
}
