import Foundation
import FoundationModels

/// What the tools can see for the current message: the folder, what's
/// installed. The conversation updates it before each message.
nonisolated final class AssistantContext: @unchecked Sendable {
    private let lock = NSLock()
    private var current: ToolInventory?

    var inventory: ToolInventory? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// The files in the current folder, so answers name real files.
nonisolated struct FolderFilesTool: Tool {
    let context: AssistantContext
    let name = "verArchivos"
    let description = "Muestra los archivos y carpetas de la carpeta en que está la persona."

    @Generable
    struct Arguments {
        @Guide(description: "Qué buscar: audio, video, imagen, pdf, documento, carpeta, o todos")
        var tipo: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let inventory = context.inventory else { return "No sé en qué carpeta está." }
        let kind = Self.kind(arguments.tipo)
        let files = inventory.files.filter { kind == nil || $0.kind == kind }.prefix(30)
        let folder = FolderName.display(inventory.directory)
        guard !files.isEmpty else { return "En \(folder) no hay archivos de ese tipo." }
        let lines = files.map { "\($0.name) (\($0.kind.rawValue), \($0.sizeText))" }
        return "En \(folder):\n" + lines.joined(separator: "\n")
    }

    private static func kind(_ text: String) -> ToolInventory.FileInfo.Kind? {
        switch AssistantEngine.normalized(text) {
        case let t where t.contains("audio"): .audio
        case let t where t.contains("video"): .video
        case let t where t.contains("imagen") || t.contains("foto"): .image
        case let t where t.contains("pdf"): .pdf
        case let t where t.contains("documento"): .document
        case let t where t.contains("carpeta"): .folder
        default: nil
        }
    }
}

/// Whether a program is installed on this Mac.
nonisolated struct InstalledTool: Tool {
    let context: AssistantContext
    let name = "estaInstalado"
    let description = "Dice si un programa de terminal está instalado en este Mac."

    @Generable
    struct Arguments {
        @Guide(description: "El nombre del programa, por ejemplo ffmpeg o git")
        var programa: String
    }

    func call(arguments: Arguments) async throws -> String {
        let name = arguments.programa.trimmingCharacters(in: .whitespaces).lowercased()
        guard let inventory = context.inventory else { return "No lo sé." }
        let installed = inventory.executables.contains(name) || inventory.brew.contains { $0.name == name }
            || inventory.npmGlobals.contains { $0.name == name }
        if installed { return "\(name) está instalado." }
        if let tool = ToolCatalog.tool(named: name) {
            return "\(name) no está instalado. Se instala con: \(tool.installCommand)"
        }
        return "\(name) no está instalado."
    }
}

/// Real examples of a command, from tldr.
nonisolated struct CommandExamplesTool: Tool {
    let name = "ejemplosDeComando"
    let description = "Da qué hace un comando de terminal y ejemplos reales de cómo usarlo."

    @Generable
    struct Arguments {
        @Guide(description: "El comando, por ejemplo tar, git o ffmpeg")
        var comando: String
    }

    func call(arguments: Arguments) async throws -> String {
        let command = arguments.comando.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        guard let page = await ToolKnowledge.shared.examples(for: command.lowercased()) else {
            return "No tengo ejemplos de \(command)."
        }
        let examples = page.examples.prefix(5).map { "- \($0.0): \($0.1)" }
        return ([page.description] + examples).joined(separator: "\n")
    }
}

/// Tools for a task, from the curated catalog and Homebrew.
nonisolated struct ToolSearchTool: Tool {
    let context: AssistantContext
    let name = "buscarHerramientas"
    let description = "Busca programas de terminal que sirven para una tarea, entre los conocidos y los de Homebrew."

    @Generable
    struct Arguments {
        @Guide(description: "La tarea en palabras clave en inglés, por ejemplo: pdf merge, video download")
        var tarea: String
    }

    func call(arguments: Arguments) async throws -> String {
        let installed = context.inventory?.executables ?? []
        var lines: [String] = []
        if let tool = ToolCatalog.match(arguments.tarea, minimumScore: 2) {
            lines.append("\(tool.id): \(tool.detail)\(installed.contains(tool.id) ? " (instalada)" : "")")
        }
        let keywords = arguments.tarea.split(separator: " ").map(String.init)
        for formula in await ToolKnowledge.shared.searchHomebrew(keywords, limit: 4) where !lines.contains(where: { $0.hasPrefix(formula.name + ":") }) {
            lines.append("\(formula.name): \(formula.summary)\(installed.contains(formula.name) ? " (instalada)" : "")")
        }
        return lines.isEmpty ? "No encontré herramientas para eso." : lines.prefix(5).joined(separator: "\n")
    }
}
