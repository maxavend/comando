import Foundation
import FoundationModels
import Testing
@testable import NativeTerminal

@Suite(.serialized, .enabled(if: AssistantEngine.isAvailable && ProcessInfo.processInfo.environment["NATIVETERM_STRESS"] != nil))
struct AssistantTimingTests {
    @Test func planTiming() async throws {
        let context = ToolInventory(directory: "/Users/demo/Proyecto", executables: ["git", "npm"])
        for request in ["corre el proyecto", "sube mis cambios a github", "convierte logo.png a jpg", "corre el proyecto"] {
            let start = ContinuousClock.now
            let session = LanguageModelSession(instructions: AssistantEngine.instructions)
            let response = try await session.respond(
                to: AssistantEngine.prompt(request, inventory: context), generating: AssistantPlan.self,
                options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 300))
            print("TIMING \(ContinuousClock.now - start) «\(request)» \(response.content.steps.map { "\($0.action) script=\($0.script ?? "-") file=\($0.file ?? "-") msg=\($0.message ?? "-") pkg=\($0.package ?? "-")" })")
        }
    }
}
