import Foundation
import FoundationModels

/// A command the assistant proposes, with where its tool comes from.
nonisolated struct AssistantProposal: Codable, Hashable, Sendable {
    var command: String
    /// “afconvert · incluida en macOS”, “storybook · script de npm”…
    var tool: String
    /// A tool the command needs that isn't installed (Homebrew package name).
    var missingPackage: String?
}

nonisolated struct AssistantReply: Sendable {
    var explanation: String
    var proposals: [AssistantProposal]
    var error: String?

    static func failure(_ message: String) -> AssistantReply {
        AssistantReply(explanation: "", proposals: [], error: message)
    }
}

/// Turns a plain-language request into commands: the on-device model picks
/// actions, and the app validates them and builds the exact commands.
nonisolated enum AssistantEngine {
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled):
            String(localized: "Activa Apple Intelligence en Ajustes del Sistema para usar el asistente.")
        case .unavailable(.modelNotReady):
            String(localized: "El modelo de Apple Intelligence todavía se está descargando. Inténtalo en unos minutos.")
        case .unavailable(.deviceNotEligible):
            String(localized: "Este Mac no es compatible con Apple Intelligence.")
        case .unavailable:
            String(localized: "Apple Intelligence no está disponible en este momento.")
        }
    }

    @concurrent
    static func reply(to request: String, inventory: ToolInventory) async -> AssistantReply {
        if let reason = unavailableReason { return .failure(reason) }
        let session = LanguageModelSession(instructions: instructions)
        let plan: AssistantPlan
        do {
            // Greedy sampling: the same request always gets the same answer.
            plan = try await session.respond(
                to: prompt(request, inventory: inventory),
                generating: AssistantPlan.self,
                options: GenerationOptions(samplingMode: .greedy)
            ).content
        } catch {
            return .failure(String(localized: "No pude procesar el pedido. Intenta decirlo de otra forma."))
        }
        return build(steps: validate(plan.steps, request: request, inventory: inventory), request: request, inventory: inventory)
    }

    // MARK: - Prompt

    static let instructions = """
    Eres el asistente de una terminal para macOS. Eliges acciones para cumplir el pedido del usuario. \
    Usa solo scripts y archivos que aparecen en el contexto. Si ninguna acción sirve, usa unknown.
    """

    static func prompt(_ request: String, inventory: ToolInventory) -> String {
        var lines = ["CARPETA: \(FolderName.display(inventory.directory))"]
        if !inventory.scripts.isEmpty {
            lines.append("SCRIPTS: \(inventory.scripts.prefix(30).joined(separator: ", "))")
        }
        if !inventory.makeTargets.isEmpty {
            lines.append("SCRIPTS (make): \(inventory.makeTargets.prefix(20).joined(separator: ", "))")
        }
        if !inventory.files.isEmpty {
            lines.append("ARCHIVOS: \(inventory.files.prefix(30).map(\.name).joined(separator: ", "))")
        }
        if !inventory.attachments.isEmpty {
            lines.append("ADJUNTOS: " + inventory.attachments.map { "\($0.name) (\($0.kind.rawValue), \($0.sizeText))" }.joined(separator: ", "))
        }
        if let git = inventory.git {
            lines.append("GIT: rama \(git.branch), \(git.changes) cambios, \(inventory.gitHasRemote ? "con remoto" : "sin remoto")")
        } else {
            lines.append("GIT: no es un repositorio")
        }
        lines.append("")
        lines.append("PEDIDO: \(request)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Validation

    /// Keeps only steps that the request actually supports, so a small model's
    /// guesses never turn into commands nobody asked for.
    static func validate(_ steps: [AssistantStep], request: String, inventory: ToolInventory) -> [AssistantStep] {
        let words = normalized(request)
        let allowsSeveral = [" y ", " luego ", " despues ", " and ", " then ", ", "].contains { " \(words) ".contains($0) }
        var result: [AssistantStep] = []
        for step in steps where step.action != .unknown {
            guard !result.contains(where: { $0.action == step.action && $0.script == step.script }) else { continue }
            guard var checked = check(step, words: words, inventory: inventory) else { continue }
            if checked.action == .resizeImage, checked.width == nil {
                checked.width = request.firstMatch(of: /(\d{2,5})/).flatMap { Int($0.1) }
                if checked.width == nil { continue }
            }
            result.append(checked)
            if !allowsSeveral { break }
        }
        return result
    }

    private static func check(_ step: AssistantStep, words: String, inventory: ToolInventory) -> AssistantStep? {
        var step = step
        func mentions(_ keys: [String]) -> Bool { keys.contains { words.contains($0) } }
        func resolveFile(_ kinds: [ToolInventory.FileInfo.Kind]) -> Bool {
            if let file = matchFile(step.file, kinds: kinds, inventory: inventory) {
                step.file = file.path
                return true
            }
            // A single attachment of the right kind is clearly “this”.
            let candidates = inventory.attachments.filter { kinds.contains($0.kind) }
            if candidates.count == 1 {
                step.file = candidates[0].path
                return true
            }
            return false
        }

        switch step.action {
        case .runScript:
            let available = inventory.scripts + inventory.makeTargets
            let script = step.script.flatMap { name in available.first { $0.caseInsensitiveCompare(name) == .orderedSame } }
                ?? available.first { words.contains(normalized($0)) }
            guard let script else { return nil }
            guard words.contains(normalized(script))
                    || mentions(["corre", "ejecuta", "inicia", "levanta", "arranca", "run", "start", "servidor", "server", "test", "prueba", "build", "compila"])
            else { return nil }
            step.script = script
        case .installDependencies:
            guard inventory.packageManager != nil, mentions(["dependencia", "instala", "install", "paquetes", "modulos"]) else { return nil }
        case .compressAudio:
            guard mentions(["audio", "sonido", "voz", "grabacion", "mp3", "m4a", "wav", "whatsapp", "podcast", "cancion"])
                    || inventory.attachments.contains(where: { $0.kind == .audio }),
                  resolveFile([.audio]) else { return nil }
        case .compressVideo:
            guard mentions(["video", "mov", "mp4", "clip", "pelicula", "grabacion de pantalla"])
                    || inventory.attachments.contains(where: { $0.kind == .video }),
                  resolveFile([.video]) else { return nil }
        case .resizeImage:
            guard mentions(["imagen", "foto", "logo", "png", "jpg", "jpeg", "ancho", "px", "achica", "redimension", "tamano", "agranda"])
                    || inventory.attachments.contains(where: { $0.kind == .image }),
                  resolveFile([.image]) else { return nil }
        case .zipFiles:
            guard mentions(["zip", "comprim", "empaquet"]), resolveFile([.folder, .other, .image, .audio, .video]) else { return nil }
        case .gitPublish:
            guard mentions(["github", "git", "sube", "subir", "push", "publica", "commit", "repositorio", "repo"]) else { return nil }
        case .gitStatus:
            guard inventory.git != nil, mentions(["cambio", "estado", "status", "modific", "git"]) else { return nil }
        case .installTool:
            guard let package = step.package?.trimmingCharacters(in: .whitespaces), !package.isEmpty,
                  package.allSatisfy({ $0.isLetter || $0.isNumber || "-_@./".contains($0) }),
                  mentions(["instala", "install", "brew", "descarga"]) else { return nil }
            step.package = package.lowercased()
        case .unknown:
            return nil
        }
        return step
    }

    /// Finds the file the model named among attachments and folder contents,
    /// tolerating a missing extension or different capitalization.
    static func matchFile(_ name: String?, kinds: [ToolInventory.FileInfo.Kind], inventory: ToolInventory) -> ToolInventory.FileInfo? {
        guard let name = name?.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")), !name.isEmpty else { return nil }
        let wanted = normalized(name)
        let candidates = (inventory.attachments + inventory.files).filter { kinds.contains($0.kind) }
        return candidates.first { normalized($0.name) == wanted || normalized($0.path) == wanted }
            ?? candidates.first { normalized(($0.name as NSString).deletingPathExtension) == wanted }
            ?? candidates.first { normalized($0.name).contains(wanted) }
    }

    // MARK: - Commands

    static func build(steps: [AssistantStep], request: String, inventory: ToolInventory) -> AssistantReply {
        guard !steps.isEmpty else {
            if let recipe = bestRecipe(for: request), recipe.parameters.isEmpty {
                return AssistantReply(
                    explanation: String(localized: "Puedo hacerlo con la receta “\(recipe.title)”."),
                    proposals: [AssistantProposal(command: recipe.command(with: [:]), tool: String(localized: "receta"))]
                )
            }
            return .failure(String(localized: "No encontré cómo hacerlo con lo que tienes instalado. Prueba con otras palabras o busca en Recetas (⌘K)."))
        }
        var explanations: [String] = []
        var proposals: [AssistantProposal] = []
        for step in steps {
            guard let (explanation, proposal) = command(for: step, inventory: inventory) else { continue }
            explanations.append(explanation)
            proposals.append(proposal)
        }
        guard !proposals.isEmpty else {
            return .failure(String(localized: "No encontré cómo hacerlo con lo que tienes instalado."))
        }
        return AssistantReply(explanation: explanations.joined(separator: " "), proposals: proposals)
    }

    private static func q(_ value: String) -> String { ShellEscape.quote(value) }

    private static func command(for step: AssistantStep, inventory: ToolInventory) -> (String, AssistantProposal)? {
        switch step.action {
        case .runScript:
            guard let script = step.script else { return nil }
            if inventory.scripts.contains(script) {
                let manager = (inventory.packageManager ?? .npm).rawValue
                let command = manager == "npm" ? "npm run \(script)" : "\(manager) run \(script)"
                return (String(localized: "Voy a ejecutar el script “\(script)” del proyecto con \(manager)."),
                        AssistantProposal(command: command, tool: "\(script) · script de \(manager)",
                                          missingPackage: inventory.has(manager) ? nil : (manager == "npm" ? "node" : manager)))
            }
            return (String(localized: "Voy a ejecutar “\(script)” del Makefile."),
                    AssistantProposal(command: "make \(script)", tool: "\(script) · Makefile"))

        case .installDependencies:
            let manager = (inventory.packageManager ?? .npm).rawValue
            return (String(localized: "Voy a instalar las dependencias del proyecto con \(manager)."),
                    AssistantProposal(command: "\(manager) install", tool: "\(manager) · \(inventory.source(of: manager))",
                                      missingPackage: inventory.has(manager) ? nil : (manager == "npm" ? "node" : manager)))

        case .compressAudio:
            guard let file = step.file else { return nil }
            let output = derivedName(file, suffix: "comprimido", extension: "m4a")
            return (String(localized: "Voy a comprimir “\((file as NSString).lastPathComponent)” a AAC de 64 kbps, ideal para enviarlo por mensaje."),
                    AssistantProposal(command: "afconvert -f m4af -d aac -b 64000 \(q(file)) \(q(output))",
                                      tool: "afconvert · \(inventory.source(of: "afconvert"))"))

        case .compressVideo:
            guard let file = step.file else { return nil }
            if inventory.has("ffmpeg") {
                let output = derivedName(file, suffix: "comprimido", extension: "mp4")
                return (String(localized: "Voy a comprimir el video con ffmpeg (H.264, buena calidad y menos peso)."),
                        AssistantProposal(command: "ffmpeg -i \(q(file)) -c:v libx264 -crf 28 -preset medium -c:a aac -b:a 128k \(q(output))",
                                          tool: "ffmpeg · \(inventory.source(of: "ffmpeg"))"))
            }
            let output = derivedName(file, suffix: "720p", extension: "mov")
            return (String(localized: "Voy a comprimir el video a 720p con la herramienta de macOS."),
                    AssistantProposal(command: "avconvert --preset Preset1280x720 --source \(q(file)) --output \(q(output))",
                                      tool: "avconvert · incluida en macOS"))

        case .resizeImage:
            guard let file = step.file, let width = step.width else { return nil }
            let ext = (file as NSString).pathExtension.isEmpty ? "png" : (file as NSString).pathExtension
            let output = derivedName(file, suffix: "\(width)px", extension: ext)
            return (String(localized: "Voy a crear una copia de “\((file as NSString).lastPathComponent)” de \(width) píxeles de ancho."),
                    AssistantProposal(command: "sips --resampleWidth \(width) \(q(file)) --out \(q(output))",
                                      tool: "sips · incluida en macOS"))

        case .zipFiles:
            guard let file = step.file else { return nil }
            let name = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            return (String(localized: "Voy a comprimir “\((file as NSString).lastPathComponent)” en un archivo .zip."),
                    AssistantProposal(command: "zip -r \(q(name + ".zip")) \(q(file))", tool: "zip · incluida en macOS"))

        case .gitPublish:
            let message = (step.message?.isEmpty == false ? step.message! : String(localized: "Actualiza el proyecto"))
                .replacingOccurrences(of: "\n", with: " ")
            let commit = "git add -A && git commit -m \(q(message))"
            let repoName = (inventory.directory as NSString).lastPathComponent
            if inventory.git == nil {
                if inventory.has("gh") {
                    return (String(localized: "Esta carpeta aún no es un repositorio: voy a crearlo, guardar los archivos y publicarlo en GitHub como privado con gh."),
                            AssistantProposal(command: "git init && \(commit) && gh repo create \(q(repoName)) --private --source=. --push",
                                              tool: "gh · \(inventory.source(of: "gh"))"))
                }
                return (String(localized: "Esta carpeta aún no es un repositorio: voy a crearlo y guardar los archivos. Para publicarlo en GitHub necesitas gh."),
                        AssistantProposal(command: "git init && \(commit)", tool: "git · incluida en macOS", missingPackage: "gh"))
            }
            if inventory.gitHasRemote {
                return (String(localized: "Voy a guardar los cambios con el mensaje “\(message)” y subirlos a GitHub."),
                        AssistantProposal(command: "\(commit) && git push", tool: "git · incluida en macOS"))
            }
            if inventory.has("gh") {
                return (String(localized: "El repositorio no está en GitHub todavía: voy a guardar los cambios y crearlo como privado con gh."),
                        AssistantProposal(command: "\(commit) && gh repo create \(q(repoName)) --private --source=. --push",
                                          tool: "gh · \(inventory.source(of: "gh"))"))
            }
            return (String(localized: "Voy a guardar los cambios. Para publicarlos en GitHub necesitas gh."),
                    AssistantProposal(command: commit, tool: "git · incluida en macOS", missingPackage: "gh"))

        case .gitStatus:
            return (String(localized: "Voy a mostrar qué cambió en el proyecto."),
                    AssistantProposal(command: "git status", tool: "git · incluida en macOS"))

        case .installTool:
            guard let package = step.package else { return nil }
            if inventory.has(package) || inventory.brew.contains(where: { $0.name == package }) {
                return (String(localized: "“\(package)” ya está instalado; voy a mostrar dónde está y su versión."),
                        AssistantProposal(command: "which \(package) && \(package) --version", tool: "\(package) · \(inventory.source(of: package))"))
            }
            guard inventory.has("brew") else { return nil }
            return (String(localized: "Voy a instalar “\(package)” con Homebrew."),
                    AssistantProposal(command: "brew install \(q(package))", tool: "Homebrew"))

        case .unknown:
            return nil
        }
    }

    /// “Entrevista.wav” → “Entrevista-comprimido.m4a”, next to the original.
    static func derivedName(_ file: String, suffix: String, extension ext: String) -> String {
        let base = (file as NSString).deletingPathExtension
        return "\(base)-\(suffix).\(ext)"
    }

    static func bestRecipe(for request: String) -> Recipe? {
        let words = Set(normalized(request).split(separator: " ").map(String.init).filter { $0.count > 3 })
        let scored = RecipeBook.all.map { recipe -> (Recipe, Int) in
            let haystack = normalized(([recipe.title, recipe.detail] + recipe.keywords).joined(separator: " "))
            return (recipe, words.count { haystack.contains($0) })
        }
        return scored.filter { $0.1 >= 2 }.max { $0.1 < $1.1 }?.0
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }
}
