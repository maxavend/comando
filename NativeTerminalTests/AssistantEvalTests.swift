import Foundation
import Testing
@testable import NativeTerminal

/// Prints how the real model answers a batch of everyday requests.
/// On with NATIVETERM_EVAL, or with a file at ~/Library/Caches/comando-eval
/// (xcodebuild doesn't pass the environment on to the tests).
@Suite(.serialized, .enabled(if: AssistantEngine.isAvailable && (ProcessInfo.processInfo.environment["NATIVETERM_EVAL"] != nil
    || FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Caches/comando-eval"))))
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

    /// Everyday terminal requests, each with what a right answer runs: how many
    /// the assistant gets right, to compare before and after a change.
    @Test func terminalScore() async {
        var context = ToolInventory(directory: "/Users/demo/Proyecto", executables: Set(ExecutableIndex.shared.names(for: ["/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])))
        context.files = [
            .init(name: "logo.png", path: "logo.png", kind: .image, size: 2_000_000),
            .init(name: "notas.md", path: "notas.md", kind: .other, size: 2_000),
            .init(name: "src", path: "src", kind: .folder, size: 0),
        ]
        context.apps = InstalledApps.list()
        let cases: [(request: String, expected: Regex<Substring>)] = [
            ("Quiero forzar el cierre de Siri", /(?:killall|pkill).*Siri/),
            ("cierra Safari", /quit app "Safari"|killall Safari/),
            ("El comando para kill la actividad", /\btop\b|\bps\b/),
            ("¿qué está usando más CPU?", /\btop\b|\bps\b/),
            ("muestra los procesos que más memoria usan", /\btop\b|\bps\b/),
            ("¿cuánto espacio me queda en el disco?", /\bdf\b/),
            ("¿qué programa está usando el puerto 3000?", /lsof.*3000/),
            ("cuenta las palabras de notas.md", /wc -w.*notas\.md/),
            ("comprime la carpeta src en un zip", /zip.*src/),
            ("¿cuánto tiempo lleva encendido el Mac?", /uptime/),
            ("que mi Mac no se duerma por una hora", /caffeinate/),
            ("muéstrame las variables de entorno", /\benv\b|printenv/),
            ("busca los archivos pdf de esta carpeta", /(?:find|ls|mdfind).*pdf/),
            ("¿cuántos píxeles mide logo.png?", /(?:sips|mdls|file).*logo\.png/),
            ("vacía la caché de DNS", /dscacheutil|mDNSResponder/),
            ("reinicia el Dock", /killall Dock/),
            ("abre Safari", /open -a.*Safari/),
            ("¿qué versión de python tengo?", /python3? (?:--version|-V)/),
            ("haz ping a google", /ping.*google/),
            ("¿cómo se llama mi Mac?", /scutil|hostname/),
            ("muestra la hora en Tokio", /TZ=.*Tokyo.*date/),
            ("¿quién está conectado a este Mac?", /\bwho\b|\busers\b|\bw\b/),
        ]
        var passed = 0
        for (request, expected) in cases {
            let start = ContinuousClock.now
            let reply = await AssistantEngine.plainReply(to: request, inventory: context)
            let commands = reply.proposals.map(\.command) + [reply.extras.template].compactMap { $0 }
            let ok = commands.contains { $0.contains(expected) }
            if ok { passed += 1 }
            print("SCORE \(ok ? "✓" : "✗") «\(request)» ⌘ \(commands) ⏱ \(ContinuousClock.now - start) \(ok ? "" : "→ \(reply.error ?? reply.explanation)")")
        }
        print("SCORE total \(passed)/\(cases.count)")
    }
}
