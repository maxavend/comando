import Foundation
import Testing
@testable import NativeTerminal

/// Prints how the real model answers a batch of everyday requests.
@Suite(.serialized, .enabled(if: AssistantEngine.isAvailable && ProcessInfo.processInfo.environment["NATIVETERM_EVAL"] != nil))
struct AssistantEvalTests {
    @Test func survey() async {
        var context = ToolInventory(directory: "/Users/demo/Proyecto", executables: Set(ExecutableIndex.shared.names(for: ["/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])))
        context.scripts = ["dev", "build", "storybook"]
        context.packageManager = .npm
        context.files = [
            .init(name: "logo.png", path: "logo.png", kind: .image, size: 2_000_000),
            .init(name: "notas.md", path: "notas.md", kind: .other, size: 2_000),
            .init(name: "src", path: "src", kind: .folder, size: 0),
        ]
        context.git = GitInfo(branch: "main", changes: 3)
        context.gitHasRemote = true
        var withPages = context
        withPages.attachments = [.init(name: "Cuestionario.pages", path: "/tmp/Cuestionario.pages", kind: .folder, size: 5_600_000)]
        for request in ["Quiero convertir este documento en pdf comprimido y que pese poco", "pasa esto a pdf"] {
            let start = ContinuousClock.now
            let reply = await AssistantEngine.reply(to: request, inventory: withPages)
            print("EVAL ⏱ \(ContinuousClock.now - start) «\(request)» → \(reply.error ?? reply.explanation) ⌘ \(reply.proposals.map(\.command))")
        }
        let requests = [
            "Hola, ¿qué tal?",
            "gracias!",
            "¿qué puedes hacer?",
            "Quiero crear una carpeta nueva",
            "crea una carpeta llamada Fotos 2026",
            "¿qué es npm?",
            "¿cuánto espacio me queda en el disco?",
            "muéstrame los archivos más pesados de esta carpeta",
            "¿cuántas líneas tiene notas.md?",
            "convierte logo.png a jpg",
            "¿qué programa está usando el puerto 3000?",
            "abre esta carpeta en finder",
            "busca la palabra TODO en el proyecto",
            "¿cuál es mi ip?",
            "descarga un video de youtube",
            "comprime un pdf",
            "corre el proyecto",
            "borra todo lo que hay en src",
            "¿cómo se llama la rama en la que estoy?",
            "muestra los procesos que más memoria usan",
            "Hola, ¿cómo comprimo un audio?",
            "achica logo.png a la mitad",
            "¿cuánto pesa la carpeta src?",
            "abre notas.md",
            "quiero saber la versión de node",
            "¿qué hora es?",
        ]
        for request in requests {
            let start = ContinuousClock.now
            let reply = await AssistantEngine.reply(to: request, inventory: context)
            print("EVAL ⏱ \(ContinuousClock.now - start)")
            print("EVAL «\(request)»\n   → \(reply.error ?? reply.explanation)\n   ⌘ \(reply.proposals.map { "\($0.command) [\($0.tool)\($0.isGenerated == true ? ", IA" : "")\($0.missingPackage.map { ", falta \($0)" } ?? "")]" }.joined(separator: " | "))\n   ↳ \(reply.extras.examples) \(reply.extras.fileRequest.map { "pide \($0.kind)" } ?? "") \(reply.extras.suggestions.map(\.package)) \(reply.extras.template ?? "")")
        }
    }
}
