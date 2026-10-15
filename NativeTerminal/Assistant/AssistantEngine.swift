import Foundation
import FoundationModels
import ImageIO
import NaturalLanguage

/// A command the assistant proposes, with where its tool comes from.
nonisolated struct AssistantProposal: Codable, Hashable, Sendable {
    var command: String
    /// “afconvert · incluida en macOS”, “storybook · script de npm”…
    var tool: String
    /// A tool the command needs that isn't installed (Homebrew package name).
    var missingPackage: String?
    /// Written by the model rather than built by the app: worth a second look.
    var isGenerated: Bool?
    /// What the tool does, in plain Spanish.
    var about: String?
    /// The command that installs a missing tool (`brew install …`, `npm install -g …`).
    var install: String?
}

/// A tool worth installing for the request, shown with an Install button.
nonisolated struct ToolSuggestion: Codable, Hashable, Sendable {
    var package: String
    var title: String
    var detail: String
    var isCask = false
    var isInstalled = false

    init(_ tool: CatalogTool, isInstalled: Bool) {
        package = tool.id
        title = tool.title
        detail = tool.detail
        isCask = tool.isCask
        self.isInstalled = isInstalled
    }

    /// A custom install command (npm), and where the tool comes from.
    var install: String?
    var origin: String?

    init(_ tool: DiscoveredTool, detail: String) {
        package = tool.package
        title = tool.command
        self.detail = detail
        isInstalled = tool.isInstalled
        install = tool.installCommand
        origin = tool.origin
    }

    var installCommand: String {
        install ?? (isCask ? "brew install --cask \(package)" : "brew install \(package)")
    }
}

/// The file a request needs but didn't name: the reply asks for it.
nonisolated struct FileRequest: Codable, Hashable, Sendable {
    var kind: ToolInventory.FileInfo.Kind
    /// Matching files in the current folder, offered as one-click answers.
    var choices: [String]
}

/// What a reply carries besides commands; stored with the entry.
nonisolated struct AssistantExtras: Codable, Hashable, Sendable {
    var fileRequest: FileRequest?
    var suggestions: [ToolSuggestion] = []
    /// Requests to try, shown as buttons (after a greeting or a miss).
    var examples: [String] = []
    /// A usage example to complete before running (“yt-dlp 'URL'”).
    var template: String?

    init(fileRequest: FileRequest? = nil, suggestions: [ToolSuggestion] = [], examples: [String] = [], template: String? = nil) {
        self.fileRequest = fileRequest
        self.suggestions = suggestions
        self.examples = examples
        self.template = template
    }

    // Tolerates replies saved before a field existed.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileRequest = try container.decodeIfPresent(FileRequest.self, forKey: .fileRequest)
        suggestions = try container.decodeIfPresent([ToolSuggestion].self, forKey: .suggestions) ?? []
        examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
        template = try container.decodeIfPresent(String.self, forKey: .template)
    }
}

nonisolated struct AssistantReply: Sendable {
    var explanation: String
    var proposals: [AssistantProposal]
    var error: String?
    var extras = AssistantExtras()

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

    /// Answers in steps, from the most reliable to the most open: small talk,
    /// known actions, a recipe or tool the model picks, a command the model
    /// writes (checked twice), and finally a short answer in words.
    @concurrent
    static func reply(to request: String, inventory: ToolInventory) async -> AssistantReply {
        if let reason = unavailableReason { return .failure(reason) }
        let words = normalized(request)
        if let smallTalk = smallTalkReply(to: words, inventory: inventory) { return smallTalk }
        // Emoji or a keyboard smash: nothing to act on.
        guard keywords(in: words).contains(where: { $0.count >= 3 }) else {
            return build(steps: [], request: request, inventory: inventory)
        }
        if let trash = trashReply(for: request, inventory: inventory) {
            return trash
        }
        if let installed = installedReply(for: request, inventory: inventory) {
            return installed
        }
        if let refusal = destructiveRefusal(for: words) {
            return refusal
        }
        // “¿Qué es npm?” or “¿para qué sirve git?” want an explanation, not a command.
        if asksForMeaning(words), let answer = await explain(request) {
            return AssistantReply(explanation: answer, proposals: [])
        }
        // A clear request needs no model: answer at once.
        if let action = guess(words, inventory: inventory) {
            let steps = validate([AssistantStep(action: action)], request: request, inventory: inventory)
            if !steps.isEmpty { return build(steps: steps, request: request, inventory: inventory) }
        }

        let plan = await ask(prompt(request, inventory: inventory), instructions: instructions, generating: AssistantPlan.self, maximumTokens: 120)
        let steps = validate(plan?.steps ?? [], request: request, inventory: inventory)
        if !steps.isEmpty {
            return build(steps: steps, request: request, inventory: inventory)
        }
        // The open-ended steps need a request in words, not a keyboard smash.
        guard looksLikeWords(request) else {
            return build(steps: [], request: request, inventory: inventory)
        }
        if let chosen = await pickOption(for: request, inventory: inventory) {
            return chosen
        }
        if let discovered = await discoverTool(for: request, inventory: inventory) {
            return discovered
        }
        if let written = await writeCommand(for: request, inventory: inventory) {
            return written
        }
        if isQuestion(request), let answer = await explain(request) {
            return AssistantReply(explanation: answer, proposals: [])
        }
        return build(steps: [], request: request, inventory: inventory)
    }

    /// One focused model call; nil if the model fails or takes too long.
    ///
    /// Greedy sampling gives the same answer to the same request, but it can
    /// also fall into repeating itself forever, so every call has a token
    /// limit and a deadline.
    private static func ask<Content: Generable & Sendable>(
        _ prompt: String, instructions: String, generating type: Content.Type,
        maximumTokens: Int = 300, timeout: Duration = .seconds(12)
    ) async -> Content? {
        await firstResult(within: timeout) {
            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: maximumTokens)
            return try? await session.respond(to: prompt, generating: type, options: options).content
        }
    }

    /// The operation's result, or nil once the deadline passes (the operation
    /// is cancelled).
    static func firstResult<T: Sendable>(within timeout: Duration, _ operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Small talk

    /// Greetings, thanks and “what can you do?”, answered instantly.
    static func smallTalkReply(to words: String, inventory: ToolInventory) -> AssistantReply? {
        let explanation: String
        if isThanks(words) {
            explanation = String(localized: "¡De nada! Cuando quieras, pídeme otra cosa.")
        } else if isGreeting(words) {
            explanation = String(localized: "¡Hola! Cuéntame qué quieres hacer, con tus palabras, y te propongo el comando. Por ejemplo:")
        } else {
            return nil
        }
        var reply = AssistantReply(explanation: explanation, proposals: [])
        reply.extras.examples = examples(for: inventory)
        return reply
    }

    private static let greetingPhrases = [
        "que puedes hacer", "que sabes hacer", "en que me ayudas", "como funciona", "quien eres", "que eres",
        "buenos dias", "buenas tardes", "buenas noches", "que tal", "como estas", "como te va",
        "hola", "holi", "buenas", "hey", "hello", "hi", "ayuda", "ayudame",
    ]
    private static let thanksPhrases = ["muchas gracias", "gracias", "thanks", "genial", "perfecto", "buenisimo", "excelente"]
    /// Words that can sit around a greeting without asking for anything.
    private static let filler: Set<String> = ["y", "tu", "todo", "bien", "como", "que", "me", "te", "a", "ti", "por", "eso", "ok", "oye", "amigo", "crack"]

    /// Only small talk: once the phrases and filler are gone, nothing is left.
    private static func isOnly(_ phrases: [String], in words: String) -> Bool {
        var text = " " + words.map { $0.isLetter ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        var found = false
        for phrase in phrases where text.contains(" \(phrase) ") {
            text = text.replacingOccurrences(of: " \(phrase) ", with: " ")
            found = true
        }
        return found && text.split(separator: " ").allSatisfy { filler.contains(String($0)) }
    }

    static func isGreeting(_ words: String) -> Bool { isOnly(greetingPhrases, in: words) }
    static func isThanks(_ words: String) -> Bool { isOnly(thanksPhrases, in: words) }

    /// “¿Qué es npm?”, but not “¿qué es lo que más pesa?”.
    static func asksForMeaning(_ words: String) -> Bool {
        let text = words.trimmingCharacters(in: CharacterSet(charactersIn: "¿? ")).trimmingCharacters(in: .whitespaces)
        if text.contains("lo que") { return false }
        return ["que es ", "que son ", "que significa", "para que sirve", "explicame", "diferencia entre", "what is "].contains { text.hasPrefix($0) }
    }

    static func isQuestion(_ request: String) -> Bool {
        let words = normalized(request).trimmingCharacters(in: .whitespaces)
        return request.contains("?") || ["que ", "como ", "cual ", "por que ", "cuando ", "donde "].contains { words.hasPrefix($0) }
    }

    // MARK: - Apps and programs on this Mac

    /// “Abre Antigravity”, “abre el CLI de Gemini”, “abre notas.md” or
    /// “¿tengo ffmpeg?”, answered from what's installed, without the model.
    static func installedReply(for request: String, inventory: ToolInventory) -> AssistantReply? {
        let words = normalized(request)
        let asksIfInstalled = ["tengo ", "esta instalad", "tienes instalad", "hay instalad", "tengo instalad"].contains(where: words.contains)
        let open = /(?i)\b(?:abre|abrir|abreme|ábreme|open|lanza|lanzar|inicia|iniciar|ejecuta|ejecutar|arranca|arrancar|entra a|entrar a)\b\s+(.+)/
        guard asksIfInstalled || words.firstMatch(of: open) != nil else { return nil }
        let target = words.firstMatch(of: open).map { String($0.1) }
            ?? words.replacing(/^.*?(tengo instalad[oa]|tengo|esta instalad[oa]|tienes instalad[oa]|hay instalad[oa])\s*/, with: "")
        let target_ = target.trimmingCharacters(in: CharacterSet(charactersIn: "¿? "))
        let wantsCommand = ["cli", "comando", "terminal de", "en la terminal", "consola"].contains(where: words.contains)

        // A file of this folder, named with its extension.
        if !asksIfInstalled, let file = (inventory.attachments + inventory.files).first(where: { words.contains(normalized($0.name)) }) {
            return AssistantReply(
                explanation: String(localized: "Voy a abrir “\(file.name)” con su app."),
                proposals: [AssistantProposal(command: "open " + q(file.path), tool: "open · incluida en macOS")]
            )
        }
        // “abre borrador.md” when there's no such file here.
        if !asksIfInstalled, let missing = target_.split(separator: " ").map(String.init)
            .first(where: { $0.firstMatch(of: /^[\w.-]+\.[a-z0-9]{1,5}$/) != nil }) {
            return AssistantReply(
                explanation: String(localized: "No encontré “\(missing)” en esta carpeta. Revisa el nombre o arrástralo a la ventana."),
                proposals: []
            )
        }
        let app = InstalledApps.findApp(target_, in: inventory.apps)
        let command = InstalledApps.findCommand(target_, app: app, executables: inventory.executables)
        guard app != nil || command != nil else {
            if asksIfInstalled, let name = InstalledApps.tokens(target_).first {
                var reply = AssistantReply(explanation: String(localized: "No encontré “\(name)” en este Mac, ni como app ni como comando."), proposals: [])
                if let tool = ToolCatalog.match(target_) {
                    reply.extras.suggestions = [ToolSuggestion(tool, isInstalled: false)]
                }
                return reply
            }
            return nil
        }

        if asksIfInstalled {
            let parts = [app.map { String(localized: "la app \($0.displayName)") }, command.map { String(localized: "el comando \($0)") }].compactMap { $0 }
            var reply = AssistantReply(
                explanation: String(localized: "Sí, tienes \(parts.formatted(.list(type: .and))).") + (app != nil ? " " + String(localized: "¿La abro?") : ""),
                proposals: []
            )
            if let app {
                reply.proposals = [AssistantProposal(command: "open -a " + q(app.name), tool: "\(app.displayName) · app instalada")]
            }
            return reply
        }
        if let command, wantsCommand || app == nil {
            let explanation = app.map { String(localized: "Voy a ejecutar \(command), el comando de \($0.displayName).") }
                ?? String(localized: "Voy a ejecutar \(command).")
            return AssistantReply(explanation: explanation,
                                  proposals: [AssistantProposal(command: command, tool: "\(command) · \(inventory.source(of: command))")])
        }
        guard let app else { return nil }
        var explanation = String(localized: "Voy a abrir \(app.displayName).")
        if let command {
            explanation += " " + String(localized: "Su comando de terminal es \(command).")
        }
        return AssistantReply(explanation: explanation,
                              proposals: [AssistantProposal(command: "open -a " + q(app.name), tool: "\(app.displayName) · app instalada")])
    }

    // MARK: - Requests that can't be acted on

    /// Text in Spanish, English or a close language; “asdfghjkl qwerty” isn't.
    static func looksLikeWords(_ request: String) -> Bool {
        guard request.split(separator: " ").count >= 2 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(request)
        let close: Set<String> = ["es", "en", "pt", "ca", "gl", "it", "fr"]
        let share = recognizer.languageHypotheses(withMaximum: 5)
            .filter { close.contains($0.key.rawValue) }.values.reduce(0, +)
        return share >= 0.5
    }

    /// “Borra todo el disco”: deleting without a named file is never proposed.
    static func destructiveRefusal(for words: String) -> AssistantReply? {
        let deletes = ["borra", "elimina", "formatea", "destruye", "delete", "wipe", "erase", "format "].contains(where: words.contains)
        let broad = ["todo", "disco", "sistema", "computador", "mac", "everything", "disk", "system"].contains(where: words.contains)
        guard deletes, broad else { return nil }
        return AssistantReply(
            explanation: String(localized: "Por seguridad no propongo borrar cosas en general. Dime qué archivo o carpeta quieres quitar y lo mando a la Papelera, donde puedes recuperarlo."),
            proposals: []
        )
    }

    // MARK: - Deleting

    /// “Borra notas.md” moves it to the Trash instead, where it can be recovered.
    /// Only when the file is what the verb acts on: “abre borrador.md” or
    /// “elimina los espacios de notas.txt” are not deletions.
    static func trashReply(for request: String, inventory: ToolInventory) -> AssistantReply? {
        let words = normalized(request)
        let pattern = /(?i)\b(?:borra|borrar|bórralo|elimina|eliminar|deshazte de|manda a la papelera|delete|remove)\s+(?:(?:el|la|los|las|mi|mis|archivo|carpeta|todo)\s+)*(?:(lo que hay en|el contenido de|todo lo que hay en|contenido de|lo de)\s+)?(?:(?:el|la|los|las|archivo|carpeta)\s+)*["“']?([^\s"”']+)/
        guard let match = words.firstMatch(of: pattern) else { return nil }
        let named = String(match.2).trimmingCharacters(in: CharacterSet(charactersIn: "?.!,"))
        let candidates = inventory.attachments + inventory.files
        guard let target = candidates.first(where: { file in
            let name = normalized(file.name)
            return name == named || normalized((file.name as NSString).deletingPathExtension) == named
        }) else { return nil }
        let contentsOnly = match.1 != nil && target.kind == .folder
        let path = contentsOnly ? ShellEscape.quote(target.path) + "/*" : ShellEscape.quote(target.path)
        let explanation = contentsOnly
            ? String(localized: "Voy a mover lo que hay en “\(target.name)” a la Papelera. Si te arrepientes, lo recuperas desde ahí.")
            : String(localized: "Voy a mover “\(target.name)” a la Papelera. Si te arrepientes, lo recuperas desde ahí.")
        return AssistantReply(
            explanation: explanation,
            proposals: [AssistantProposal(command: "trash " + path, tool: "trash · incluida en macOS")]
        )
    }

    // MARK: - Explaining

    private static let explainInstructions = """
    Explicas temas de la terminal, la programación y macOS a personas que no son expertas. \
    Responde en español, en dos oraciones como máximo, con palabras simples. No uses listas ni código.
    """

    @concurrent
    static func explain(_ request: String) async -> String? {
        let text = await firstResult(within: .seconds(12)) {
            let session = LanguageModelSession(instructions: explainInstructions)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 120)
            return try? await session.respond(to: request, options: options).content
        }
        return cleanMessage(text)
    }

    // MARK: - Recipes and tools

    /// Recipes and tools whose words overlap the request, for the model to choose from.
    static func candidates(for request: String) -> (recipes: [Recipe], tools: [CatalogTool]) {
        let words = normalized(request)
        // Two shared words, or every word of a short request.
        let needed = min(2, max(1, keywords(in: words).count))
        let recipes = RecipeBook.all.map { ($0, overlap(words, $0)) }.filter { $0.1 >= needed }
            .sorted { $0.1 > $1.1 }.prefix(5).map(\.0)
        let tools = ToolCatalog.all.map { ($0, ToolCatalog.score($0, for: words)) }.filter { $0.1 >= 2 }
            .sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
        return (recipes, tools)
    }

    private static let pickInstructions = """
    Eliges cuál de las opciones numeradas cumple el pedido de una persona en una terminal de macOS. \
    Elige una opción solo si hace lo que se pide; si ninguna lo hace, responde 0.
    """

    @concurrent
    static func pickOption(for request: String, inventory: ToolInventory) async -> AssistantReply? {
        // Only recipes: tools are found by discoverTool, with real examples.
        let recipes = candidates(for: request).recipes
        guard !recipes.isEmpty else { return nil }
        let options = recipes.map { "\($0.title): \($0.detail)" }
        let prompt = "PEDIDO: \(request)\n\nOPCIONES:\n" + options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        guard let choice = await ask(prompt, instructions: pickInstructions, generating: OptionChoice.self, maximumTokens: 10),
              choice.option >= 1, choice.option <= options.count else { return nil }
        return useRecipe(recipes[choice.option - 1], request: request, inventory: inventory)
    }


    static func isInstalled(_ tool: CatalogTool, inventory: ToolInventory) -> Bool {
        inventory.has(tool.command) || inventory.brew.contains { $0.name == tool.id }
    }

    // MARK: - Finding a tool for the job

    /// Prints each step of tool discovery, for tests and debugging.
    nonisolated(unsafe) static var trace: ((String) -> Void)?

    private static let termsInstructions = """
    Conviertes el pedido de una persona en palabras clave en inglés para buscar herramientas de terminal.
    """

    private static let discoverInstructions = """
    Escribes un solo comando de zsh para macOS que cumple el pedido usando una de las HERRAMIENTAS. \
    Adapta uno de sus EJEMPLOS; usa ARCHIVOS o ADJUNTOS solo si aparecen. \
    Nunca copies valores de los ejemplos que el pedido no menciona (ciudades, números, nombres): quita esas opciones. \
    Si hay que inventar un archivo de salida, nómbralo a partir del de entrada. \
    Nunca uses sudo ni borres archivos. Si ninguna herramienta sirve, deja el comando vacío.
    """

    /// Looks for a terminal tool that does the job (installed, in Homebrew or
    /// on npm), shows the model real examples of it, and has it write the
    /// command. Says what each tool does, in Spanish.
    @concurrent
    static func discoverTool(for request: String, inventory: ToolInventory) async -> AssistantReply? {
        guard AppSettings.searchesToolsOnline,
              let terms = await ask(request, instructions: termsInstructions, generating: SearchTerms.self, maximumTokens: 40, timeout: .seconds(6)),
              !terms.keywords.isEmpty else { return nil }
        let keywords = Array(terms.keywords.prefix(6))
        let ranked = await candidateTools(for: request, keywords: keywords, inventory: inventory)
        let tools = ranked.map(\.tool)
        trace?("keywords \(keywords) → \(ranked.map { "\($0.tool.command)\($0.tool.isInstalled ? "✓" : "") \($0.score)" })")
        guard !tools.isEmpty else { return nil }

        var examples: [String: ToolExamples] = [:]
        for tool in tools {
            examples[tool.command] = await ToolKnowledge.shared.examples(for: tool.command)
        }
        var context = ["HERRAMIENTAS:"]
        for tool in tools {
            let page = examples[tool.command]
            context.append("- \(tool.command) (\(tool.isInstalled ? "instalada" : "no instalada")): \(page?.description ?? tool.summary)")
            for (what, command) in page?.examples.prefix(4) ?? [] {
                context.append("  EJEMPLO \(what): \(command)")
            }
        }
        // Only the files the request is about: a list of every file in the
        // folder tempts the model to stuff them into the command.
        let named = inventory.files.filter { mentionsFile($0, in: normalized(request)) }
        if !named.isEmpty {
            context.append("ARCHIVOS: \(named.map(\.name).joined(separator: ", "))")
        }
        if !inventory.attachments.isEmpty {
            context.append("ADJUNTOS: \(inventory.attachments.map(\.path).joined(separator: ", "))")
        }
        let prompt = context.joined(separator: "\n") + "\n\nPEDIDO: \(request)"
        let written = await ask(prompt, instructions: discoverInstructions, generating: WrittenCommand.self, maximumTokens: 120)
        trace?("escribió: \(written?.command ?? "nada")")
        // The command must be built on one of the tools found: those come with
        // real examples, unlike whatever the model remembers.
        var proposal = written.flatMap { checkCommand($0.command, request: request, inventory: inventory, tools: tools) }
        let programs = proposal.map { $0.command.split(separator: /\|\||&&|\||;/).compactMap { ShellEscape.words(String($0)).first } } ?? []
        let used = tools.first { programs.first == $0.command }
        // Built on a found tool, or on one already installed (“git branch”).
        if used == nil, !(programs.first.map(inventory.has) ?? false) { proposal = nil }
        trace?("aceptado: \(proposal?.command ?? "no")")

        // What each tool does, in Spanish: the one used (or the best one) and
        // up to two others.
        if proposal != nil, used == nil, let written, var proposal {
            // An installed program the search didn't need to find.
            proposal.isGenerated = true
            return AssistantReply(explanation: sentence(written.explanation), proposals: [proposal])
        }
        // Without a command, only point to a tool that clearly fits.
        if proposal == nil, (ranked.first?.score ?? 0) < 6 { return nil }
        let chosen = used ?? tools[0]
        let others = Array(tools.filter { $0 != chosen }.prefix(2))
        let descriptions = await spanishDescriptions(for: [chosen] + others, examples: examples)
        let about = descriptions[chosen.command] ?? chosen.summary
        var reply: AssistantReply
        if var proposal, let written, !usesMadeUpFiles(proposal.command, request: request, inventory: inventory) {
            proposal.about = about
            reply = AssistantReply(explanation: sentence(written.explanation), proposals: [proposal])
        } else if let proposal, let written {
            // “input.mp4” is an example, not a file: show it to be completed.
            reply = AssistantReply(explanation: sentence(written.explanation) + " " + String(localized: "Cambia los nombres de archivo por los tuyos:"), proposals: [])
            reply.extras.template = proposal.command
            if !chosen.isInstalled { reply.extras.suggestions.append(ToolSuggestion(chosen, detail: about)) }
        } else {
            // No usable command: say which tool fits and how it's used.
            let state = chosen.isInstalled ? String(localized: "ya la tienes") : String(localized: "no la tienes instalada")
            reply = AssistantReply(
                explanation: String(localized: "Para eso sirve \(chosen.command) (\(state)): \(about.lowercasedFirst)") + " "
                    + String(localized: "Se usa así; edítalo con tus datos:"),
                proposals: []
            )
            reply.extras.template = examples[chosen.command]?.examples.first?.1 ?? "\(chosen.command) --help"
            if !chosen.isInstalled {
                reply.extras.suggestions.append(ToolSuggestion(chosen, detail: about))
            }
        }
        reply.extras.suggestions += others.map { ToolSuggestion($0, detail: descriptions[$0.command] ?? $0.summary) }
        return reply
    }

    /// Tools that may do the job: installed ones first, then the curated
    /// catalog, Homebrew, and npm when the rest isn't enough.
    static func candidateTools(for request: String, keywords: [String], inventory: ToolInventory) async -> [(tool: DiscoveredTool, score: Int)] {
        var scored: [(tool: DiscoveredTool, score: Int)] = []
        func add(_ tool: DiscoveredTool, score: Int) {
            if let index = scored.firstIndex(where: { $0.tool.command == tool.command || $0.tool.package == tool.package }) {
                scored[index].score = max(scored[index].score, score)
            } else {
                scored.append((tool, score))
            }
        }
        // The curated catalog knows Spanish words, so it scores high.
        let words = normalized(request)
        for tool in ToolCatalog.all {
            let score = ToolCatalog.score(tool, for: words)
            guard score >= 2 else { continue }
            add(DiscoveredTool(package: tool.id, command: tool.command, summary: tool.detail, source: .homebrew,
                               isInstalled: isInstalled(tool, inventory: inventory)), score: score + 4)
        }
        for formula in await ToolKnowledge.shared.searchHomebrew(keywords, limit: 8) {
            let command = ToolCatalog.tool(named: formula.name)?.command ?? formula.name
            add(DiscoveredTool(package: formula.name, command: command, summary: formula.summary, source: .homebrew,
                               isInstalled: inventory.has(command) || inventory.brew.contains { $0.name == formula.name }),
                score: formula.score)
        }
        if scored.filter({ $0.score >= 4 }).count < 2 {
            for var tool in await ToolKnowledge.shared.searchNPM(keywords) {
                tool.isInstalled = inventory.has(tool.command)
                add(tool, score: 3)
            }
        }
        // How well it matches comes first; being installed helps break ties.
        let ranked = scored.sorted { ($0.score + ($0.tool.isInstalled ? 2 : 0)) > ($1.score + ($1.tool.isInstalled ? 2 : 0)) }
        // A single loose word in common is chance, not a match (“sándwich” → bfs).
        let best = ranked.first?.score ?? 0
        guard best >= 4 else { return [] }
        return Array(ranked.filter { $0.score * 2 >= best }.prefix(4))
    }

    /// Spanish one-liners: tldr's own when it has a Spanish page, the curated
    /// catalog's, or a short translation by the model.
    static func spanishDescriptions(for tools: [DiscoveredTool], examples: [String: ToolExamples]) async -> [String: String] {
        var result: [String: String] = [:]
        var pending: [DiscoveredTool] = []
        for tool in tools {
            if let page = examples[tool.command], page.isSpanish, !page.description.isEmpty {
                result[tool.command] = firstSentence(page.description)
            } else if let curated = ToolCatalog.tool(named: tool.command) ?? ToolCatalog.tool(named: tool.package) {
                result[tool.command] = curated.detail
            } else {
                pending.append(tool)
            }
        }
        guard !pending.isEmpty else { return result }
        let english = pending.map { firstSentence(examples[$0.command]?.description ?? $0.summary) }
        let prompt = english.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        if let translated = await ask(prompt, instructions: "Traduces descripciones de herramientas al español.", generating: Translations.self, maximumTokens: 120),
           translated.lines.count == pending.count {
            for (tool, line) in zip(pending, translated.lines) { result[tool.command] = sentence(line) }
        } else {
            for (tool, line) in zip(pending, english) { result[tool.command] = line }
        }
        return result
    }

    // MARK: - Commands the model writes

    private static let writeInstructions = """
    Escribes un solo comando de zsh para macOS que cumple el pedido de una persona. \
    Usa programas que vienen con macOS cuando se pueda. Nunca uses sudo ni borres archivos. \
    Usa solo nombres de archivos que aparecen en ARCHIVOS. Si no sabes un comando que lo haga, deja el comando vacío.
    Ejemplos:
    cuántas líneas tiene notas.md → wc -l notas.md
    los archivos más pesados de esta carpeta → du -sh * | sort -rh | head -10
    en qué rama estoy → git branch --show-current
    convierte foto.png a jpg → sips -s format jpeg foto.png --out foto.jpg
    busca la palabra hola en el proyecto → grep -rn "hola" .
    """

    private static let checkInstructions = """
    Revisas si un comando de terminal de macOS hace exactamente lo que pide una persona. Sé estricto.
    """

    @concurrent
    static func writeCommand(for request: String, inventory: ToolInventory) async -> AssistantReply? {
        var context = ["CARPETA: \(FolderName.display(inventory.directory))"]
        if !inventory.files.isEmpty {
            context.append("ARCHIVOS: \(inventory.files.prefix(30).map(\.name).joined(separator: ", "))")
        }
        if !inventory.attachments.isEmpty {
            context.append("ADJUNTOS: \(inventory.attachments.map(\.path).joined(separator: ", "))")
        }
        let installed = InstalledApps.related(to: request, inventory: inventory)
        if !installed.isEmpty {
            context.append("INSTALADO: \(installed.joined(separator: ", "))")
        }
        let prompt = context.joined(separator: "\n") + "\n\nPEDIDO: \(request)"
        guard let written = await ask(prompt, instructions: writeInstructions, generating: WrittenCommand.self, maximumTokens: 100),
              let proposal = checkCommand(written.command, request: request, inventory: inventory) else { return nil }
        // A second, independent look catches commands that run but miss the point.
        let review = "PEDIDO: \(request)\nCOMANDO: \(proposal.command)"
        guard let check = await ask(review, instructions: checkInstructions, generating: CommandCheck.self, maximumTokens: 10), check.matches else { return nil }
        let explanation = cleanMessage(written.explanation).map { sentence($0) }
            ?? CommandGlossary.describe(proposal.command).map { $0 + "." }
            ?? String(localized: "Este comando debería hacerlo.")
        return AssistantReply(explanation: explanation, proposals: [proposal])
    }

    /// Reads files the request never gave (“input.mp4”), so it's an example.
    static func usesMadeUpFiles(_ command: String, request: String, inventory: ToolInventory) -> Bool {
        guard inventory.attachments.isEmpty else { return false }
        let words = normalized(request)
        if inventory.files.contains(where: { mentionsFile($0, in: words) }) { return false }
        let fileLike = ShellEscape.words(command).dropFirst().filter { $0.firstMatch(of: /^[\w.\/-]+\.[a-zA-Z0-9]{2,5}$/) != nil }
        return !fileLike.isEmpty
    }

    /// The first sentence of a description, without “See also” notes.
    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let end = trimmed.firstMatch(of: /[.!?](\s|$)/) else { return sentence(trimmed) }
        return String(trimmed[..<end.range.lowerBound]) + "."
    }

    /// Capitalized and ending with a period.
    static func sentence(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first { text = first.uppercased() + text.dropFirst() }
        if let last = text.last, !".!?".contains(last) { text += "." }
        return text
    }

    /// The model's own words, if they are short enough to be a reply.
    static func cleanMessage(_ message: String?) -> String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 500 else { return nil }
        return text
    }

    /// Accepts a command the model wrote only if every program in it exists
    /// (or can be installed), the syntax is valid, nothing in it is risky, and
    /// it doesn't make up web addresses or write files nobody asked for.
    static func checkCommand(_ command: String, request: String, inventory: ToolInventory, tools: [DiscoveredTool] = []) -> AssistantProposal? {
        var line = command.trimmingCharacters(in: .whitespacesAndNewlines)
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        if line.hasPrefix("$ ") { line.removeFirst(2) }
        let words = normalized(request)
        let tokens = ShellEscape.words(line)
        guard !line.isEmpty, !line.contains("\n"), line.count <= 300,
              DangerDetector.risk(of: line) == nil,
              // Nothing that runs hidden code, changes or deletes files, or
              // installs things: those have their own, reviewed flows.
              !line.contains("$("), !line.contains("`"), !line.contains("<"),
              !tokens.contains(where: { Self.forbiddenWords.contains($0) }),
              !tokens.contains(where: { $0.hasPrefix("-delete") || $0 == "-exec" || $0 == "-execdir" }),
              !zip(tokens, tokens.dropFirst()).contains(where: { Self.interpreters.contains($0) && ["-c", "-e"].contains($1) }),
              !zip(tokens, tokens.dropFirst()).contains(where: { $0 == "sed" && $1.hasPrefix("-i") }),
              !zip(tokens, tokens.dropFirst()).contains(where: { ["git", "brew", "npm", "pip", "pip3", "pipx", "uv", "gem"].contains($0) && Self.changingVerbs.contains($1) }),
              !line.contains("http") || request.contains("http"),
              writesOnlyNewFiles(line, request: words, inventory: inventory) else { return nil }

        var programs: [String] = []
        for segment in line.split(separator: /\|\||&&|\||;/) {
            let segmentWords = ShellEscape.words(String(segment)).drop { $0.contains("=") && !$0.hasPrefix("-") }
            guard let program = segmentWords.first else { return nil }
            programs.append(program)
        }
        guard let first = programs.first else { return nil }
        var missing: String?
        var install: String?
        for program in programs where !inventory.has(program) && !shellBuiltins.contains(program) {
            // An unknown program is fine only if it's a known tool to install.
            guard missing == nil else { return nil }
            if let tool = tools.first(where: { $0.command == program }), let command = tool.installCommand {
                missing = tool.package
                install = command
            } else if let tool = ToolCatalog.tool(named: program) {
                missing = tool.id
                install = tool.installCommand
            } else {
                return nil
            }
        }
        guard ToolInventory.run(["zsh", "-n", "-c", line]) != nil else { return nil }
        let source = tools.first { $0.command == first }.map(\.origin) ?? inventory.source(of: first)
        return AssistantProposal(command: line, tool: "\(first) · \(source)",
                                 missingPackage: missing, isGenerated: true, install: install)
    }

    private static let forbiddenWords: Set<String> = [
        "sudo", "su", "rm", "rmdir", "trash", "kill", "killall", "pkill", "shutdown", "reboot", "halt", "mv", "cp",
        "chmod", "chown", "dd", "tee", "xargs", "eval", "exec", "source", ".", "launchctl", "defaults", "osascript",
        "diskutil", "truncate", "shred", "ln",
    ]
    private static let interpreters: Set<String> = ["sh", "bash", "zsh", "python", "python3", "node", "ruby", "perl", "osascript"]
    private static let changingVerbs: Set<String> = [
        "reset", "clean", "checkout", "restore", "push", "rebase", "rm", "commit", "merge", "stash", "switch",
        "install", "uninstall", "upgrade", "update", "remove", "add", "i", "un", "link", "unlink",
    ]

    /// A `>` only when the person asked to save something, and only into a
    /// new file: never one that exists or that the command itself reads
    /// (`sort notas.md > notas.md` empties it).
    private static func writesOnlyNewFiles(_ line: String, request: String, inventory: ToolInventory) -> Bool {
        guard line.contains(">") else { return true }
        guard ["guard", "export", "escrib", "crea", "archivo nuevo"].contains(where: request.contains),
              !line.contains(">>"), line.filter({ $0 == ">" }).count == 1,
              let match = line.firstMatch(of: />\s*(\S+)/) else { return false }
        let target = String(match.1).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        let path = target.hasPrefix("/") ? target : (inventory.directory as NSString).appendingPathComponent(target)
        let reads = ShellEscape.words(String(line[..<match.range.lowerBound]))
        return !target.hasPrefix("/dev") && !reads.contains(target)
            && !inventory.files.contains { $0.name == target || $0.path == target }
            && !FileManager.default.fileExists(atPath: path)
    }

    private static let shellBuiltins: Set<String> = [
        "cd", "echo", "printf", "export", "test", "[", "pwd", "for", "while", "if", "read", "true", "false", "type", "which", "time",
    ]

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
        // When the model finds nothing usable, plain keywords still can.
        let candidates = steps.contains { check($0, words: words, inventory: inventory) != nil }
            ? steps : steps + [guess(words, inventory: inventory)].compactMap { $0.map { AssistantStep(action: $0) } }
        for step in candidates where step.action != .unknown {
            guard !result.contains(where: { $0.action == step.action && $0.script == step.script }) else { continue }
            guard var checked = check(step, words: words, inventory: inventory) else { continue }
            if checked.action == .convertToPDF {
                checked.compress = ["comprim", "pese poco", "liviano", "ligero", "reduc", "achic", "chico", "menos"].contains(where: words.contains)
            }
            if checked.action == .resizeImage {
                // Only a width the person wrote, or a fraction of the real one;
                // otherwise a common size they can edit.
                checked.width = requestedWidth(request, file: checked.file, inventory: inventory) ?? defaultImageWidth
            }
            result.append(checked)
            if !allowsSeveral { break }
        }
        return result
    }

    private static func check(_ step: AssistantStep, words: String, inventory: ToolInventory) -> AssistantStep? {
        var step = step
        func mentions(_ keys: [String]) -> Bool { keys.contains { words.contains($0) } }
        /// Points the step at a real file, or clears it so the reply asks
        /// which one (never a file the model made up).
        func resolveFile(_ kinds: [ToolInventory.FileInfo.Kind]) -> Bool {
            // A folder file counts only when the request names it; attachments
            // were given on purpose.
            if let file = matchFile(step.file, kinds: kinds, inventory: inventory),
               inventory.attachments.contains(file) || mentionsFile(file, in: words) {
                step.file = file.path
                return true
            }
            // A single attachment of the right kind is clearly “this”, and so
            // is a file of the folder the request names.
            let candidates = inventory.attachments.filter { kinds.contains($0.kind) }
            let named = inventory.files.filter { kinds.contains($0.kind) && mentionsFile($0, in: words) }
            step.file = candidates.count == 1 ? candidates[0].path : named.count == 1 ? named[0].path : nil
            return true
        }

        switch step.action {
        case .runScript:
            let available = inventory.scripts + inventory.makeTargets
            let script = step.script.flatMap { name in available.first { $0.caseInsensitiveCompare(name) == .orderedSame } }
                ?? available.first { words.contains(normalized($0)) }
                // “Corre el proyecto” means its development server; “los tests”, its tests.
                ?? (mentions(["test", "prueba"]) ? ["test", "tests"].first(where: available.contains) : nil)
                ?? (mentions(["proyecto", "servidor", "server", "app", "sitio", "web"])
                    ? ["dev", "start", "serve"].first(where: available.contains) : nil)
            guard var script else { return nil }
            // “Corre el proyecto” names no script: the dev server beats a guess like “build”.
            if !words.contains(normalized(script)), mentions(["proyecto", "servidor", "server", "app", "sitio", "web"]),
               let server = ["dev", "start", "serve"].first(where: available.contains) {
                script = server
            }
            guard words.contains(normalized(script))
                    || mentions(["corre", "ejecuta", "inicia", "levanta", "arranca", "run", "start", "servidor", "server", "test", "prueba", "build", "compila"])
            else { return nil }
            step.script = script
        case .installDependencies:
            guard inventory.packageManager != nil, mentions(["dependencia", "instala", "install", "paquetes", "modulos"]) else { return nil }
        case .compressAudio:
            // “Descargar un audio” is not compressing one.
            guard mentions(audioWords) || inventory.attachments.contains(where: { $0.kind == .audio }),
                  mentions(shrinkWords),
                  resolveFile([.audio]) else { return nil }
        case .compressVideo:
            guard mentions(videoWords) || inventory.attachments.contains(where: { $0.kind == .video }),
                  mentions(shrinkWords + ["720"]),
                  resolveFile([.video]) else { return nil }
        case .resizeImage:
            // “Convierte a jpg” is not a resize: it needs words about size.
            guard mentions(imageWords) || inventory.attachments.contains(where: { $0.kind == .image }),
                  mentions(sizeWords) || words.contains(/\d{2,5}/),
                  resolveFile([.image]) else { return nil }
        case .convertToPDF, .compressPDF:
            // “Que pese menos” about an attached PDF or document counts too.
            guard mentions(["pdf"]) || inventory.attachments.contains(where: { $0.kind == .pdf || $0.kind == .document }) else { return nil }
            // Shrinking needs a PDF; a document is converted first.
            let hasDocument = inventory.attachments.contains { $0.kind == .document }
                || inventory.files.contains { $0.kind == .document && mentionsFile($0, in: words) }
            let hasPDF = inventory.attachments.contains { $0.kind == .pdf }
                || inventory.files.contains { $0.kind == .pdf && mentionsFile($0, in: words) }
            if step.action == .compressPDF, !hasPDF, hasDocument || mentions(documentWords) {
                step.action = .convertToPDF
            }
            if step.action == .convertToPDF, !hasDocument, hasPDF {
                step.action = .compressPDF
            }
            if step.action == .compressPDF, !mentions(shrinkWords) { return nil }
            // “Convierte notas.md a pdf”: Pages can't open that, another tool can.
            if step.action == .convertToPDF, !hasDocument,
               inventory.files.contains(where: { $0.kind != .document && $0.kind != .pdf && mentionsFile($0, in: words) }) { return nil }
            _ = resolveFile(step.action == .convertToPDF ? [.document] : [.pdf])
        case .zipFiles:
            // “Comprimir un audio” means a smaller audio, not a .zip.
            guard mentions(["zip", "empaquet"])
                    || (mentions(["comprim"]) && !mentions(audioWords + videoWords + imageWords + documentWords + ["pdf"])),
                  resolveFile([.folder, .other, .image, .audio, .video]) else { return nil }
        case .gitPublish:
            guard mentions(["github", "git", "sube", "subir", "push", "publica", "commit", "repositorio", "repo"]) else { return nil }
        case .gitStatus:
            guard inventory.git != nil, mentions(["cambio", "estado", "status", "modific", "git"]) else { return nil }
        case .installTool:
            guard let package = step.package?.trimmingCharacters(in: .whitespaces), !package.isEmpty,
                  package.allSatisfy({ $0.isLetter || $0.isNumber || "-_@./".contains($0) }),
                  mentions(["instala", "install", "brew", "descarga"]) else { return nil }
            // “instala magick” → the imagemagick package.
            step.package = ToolCatalog.tool(named: package.lowercased())?.id ?? package.lowercased()
        case .unknown:
            return nil
        }
        return step
    }

    /// How many meaningful words of the request a recipe shares (“carpetas”
    /// matches “carpeta”).
    static func overlap(_ words: String, _ recipe: Recipe) -> Int {
        let haystack = keywords(in: ([recipe.title, recipe.detail, recipe.id] + recipe.keywords).joined(separator: " "))
        return keywords(in: words).count { word in
            haystack.contains { $0 == word || (min($0.count, word.count) >= 4 && ($0.hasPrefix(word) || word.hasPrefix($0))) }
        }
    }

    /// Words that carry meaning: no punctuation, accents or Spanish filler.
    static func keywords(in text: String) -> Set<String> {
        let cleaned = normalized(text).map { $0.isLetter || $0.isNumber ? $0 : " " }
        return Set(String(cleaned).split(separator: " ").map(String.init).filter { $0.count >= 2 && !stopwords.contains($0) })
    }

    private static let stopwords: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "al", "en", "con", "por", "para", "que", "y", "o",
        "mi", "mis", "tu", "tus", "su", "sus", "me", "te", "se", "lo", "le", "es", "son", "esta", "este", "esto", "eso",
        "hay", "como", "cual", "quiero", "quisiera", "puedo", "puedes", "hacer", "hago", "ver", "muestra", "muestrame",
        "dime", "favor", "porfa", "hola", "aqui", "ahora", "todo", "todos", "mas", "muy", "the", "a", "an", "to", "of", "my",
    ]

    static let defaultImageWidth = 1200

    /// “800 px” → 800; “a la mitad” or “al 25 %” → that share of the image's width.
    static func requestedWidth(_ request: String, file: String?, inventory: ToolInventory) -> Int? {
        let words = normalized(request)
        var fraction: Double?
        if let percent = words.firstMatch(of: /(\d{1,3})\s*(%|por ?ciento)/), let value = Double(percent.1) {
            fraction = value / 100
        } else if words.contains("mitad") {
            fraction = 0.5
        } else if words.contains("tercio") {
            fraction = 1.0 / 3
        } else if words.contains("cuarta parte") || words.contains("un cuarto") {
            fraction = 0.25
        }
        if let fraction {
            guard let file, let width = imageWidth(of: file, in: inventory.directory) else { return nil }
            return max(1, Int((Double(width) * fraction).rounded()))
        }
        return words.firstMatch(of: /(\d{2,5})/).flatMap { Int($0.1) }
    }

    static func imageWidth(of file: String, in directory: String) -> Int? {
        let url = file.hasPrefix("/") ? URL(filePath: file) : URL(filePath: directory, directoryHint: .isDirectory).appending(path: file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return properties[kCGImagePropertyPixelWidth] as? Int
    }

    private static let audioWords = ["audio", "sonido", "voz", "grabacion", "mp3", "m4a", "wav", "whatsapp", "podcast", "cancion", "musica"]
    private static let videoWords = ["video", "mov", "mp4", "clip", "pelicula", "grabacion de pantalla"]
    /// Words that ask for a smaller or converted file, or one ready to send.
    private static let shrinkWords = ["comprim", "achic", "reduc", "liviano", "pesa", "peso", "convert", "pasar a", "chico",
                                      "mp3", "m4a", "whatsapp", "mandar", "enviar", "correo", "mail", "pese poco", "pese menos", "menos peso", "ligero", "liviano"]
    private static let documentWords = ["documento", "word", "docx", "pages", "presentacion", "keynote", "planilla", "excel", "numbers"]
    private static let sizeWords = ["mitad", "tercio", "%", "por ciento", "achic", "redimension", "tamano", "ancho", "px", "agrand", "reduc", "pequen", "mas chica", "mas grande"]
    private static let imageWords = ["imagen", "foto", "logo", "png", "jpg", "jpeg", "heic"]

    /// The action a request clearly asks for by its words alone.
    static func guess(_ words: String, inventory: ToolInventory) -> AssistantAction? {
        func mentions(_ keys: [String]) -> Bool { keys.contains { words.contains($0) } }
        func attached(_ kind: ToolInventory.FileInfo.Kind) -> Bool { inventory.attachments.contains { $0.kind == kind } }
        if mentions(["pdf"]) || attached(.pdf) || attached(.document) {
            if mentions(documentWords + ["convert", "pasa", "exporta", "transforma", "a pdf", "en pdf"]) || attached(.document) {
                if mentions(["pdf"]) || attached(.document) && mentions(shrinkWords) { return .convertToPDF }
            }
            if mentions(shrinkWords) && (mentions(["pdf"]) || attached(.pdf)) { return .compressPDF }
        }
        if mentions(audioWords) || attached(.audio), mentions(shrinkWords) { return .compressAudio }
        if mentions(videoWords) || attached(.video), mentions(shrinkWords + ["720"]) { return .compressVideo }
        if mentions(imageWords) || attached(.image), mentions(sizeWords) { return .resizeImage }
        if mentions(["zip", "empaquet"]) { return .zipFiles }
        let run = ["corre", "correr", "ejecuta", "levanta", "inicia", "arranca", "run ", "start"]
        if mentions(run), mentions(["proyecto", "servidor", "server", "app", "test", "prueba", "build", "compila"])
            || inventory.scripts.contains(where: { mentions(["corre " + normalized($0), "ejecuta " + normalized($0)]) }) {
            return .runScript
        }
        if mentions(["instala", "install"]), mentions(["dependencia", "paquetes", "modulos"]) { return .installDependencies }
        if mentions(["sube", "subir", "publica", "push"]), mentions(["github", "git ", "cambios", "repo"]) { return .gitPublish }
        return nil
    }

    /// Whether the request names the file, with or without its extension.
    static func mentionsFile(_ file: ToolInventory.FileInfo, in words: String) -> Bool {
        let name = normalized(file.name)
        let base = normalized((file.name as NSString).deletingPathExtension)
        return words.contains(name) || (base.count >= 3 && words.contains(base))
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
            if let smallTalk = smallTalkReply(to: normalized(request), inventory: inventory) {
                return smallTalk
            }
            if let recipe = bestRecipe(for: request) {
                return useRecipe(recipe, request: request, inventory: inventory)
            }
            if let tool = ToolCatalog.match(request, minimumScore: 4) {
                return recommend(tool, inventory: inventory)
            }
            var reply = AssistantReply.failure(String(localized: "Todavía no sé hacer eso. Prueba con algo como:"))
            reply.extras.examples = examples(for: inventory)
            return reply
        }
        if let step = steps.first(where: { $0.needsFile && $0.file == nil }) {
            return askForFile(for: step, inventory: inventory)
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
        var reply = AssistantReply(explanation: explanations.joined(separator: " "), proposals: proposals)
        reply.extras.suggestions = steps.compactMap { upgradeSuggestion(for: $0.action, inventory: inventory) }
        return reply
    }

    /// The request names no file: say which tool will do it and ask for one.
    static func askForFile(for step: AssistantStep, inventory: ToolInventory) -> AssistantReply {
        let kind: ToolInventory.FileInfo.Kind
        let explanation: String
        switch step.action {
        case .compressAudio:
            kind = .audio
            explanation = String(localized: "Puedo comprimirlo con afconvert, que ya viene en macOS. ¿Qué audio quieres comprimir? Arrástralo a la ventana o elígelo.")
        case .compressVideo:
            kind = .video
            explanation = inventory.has("ffmpeg")
                ? String(localized: "Puedo comprimirlo con FFmpeg, que ya tienes instalado. ¿Qué video quieres comprimir? Arrástralo a la ventana o elígelo.")
                : String(localized: "Puedo comprimirlo con avconvert, que ya viene en macOS. ¿Qué video quieres comprimir? Arrástralo a la ventana o elígelo.")
        case .resizeImage:
            kind = .image
            explanation = String(localized: "Puedo cambiarle el tamaño con sips, que ya viene en macOS. ¿Qué imagen? Arrástrala a la ventana o elígela.")
        case .convertToPDF:
            kind = .document
            explanation = String(localized: "Puedo exportarlo a PDF con Pages, Numbers o Keynote, que vienen con tu Mac. ¿Qué documento? Arrástralo a la ventana o elígelo.")
        case .compressPDF:
            kind = .pdf
            explanation = String(localized: "Puedo reducir su peso con comprimir-pdf, que viene con Comando. ¿Qué PDF? Arrástralo a la ventana o elígelo.")
        default:
            kind = .other
            explanation = String(localized: "Puedo comprimirlo en un .zip con la herramienta de macOS. ¿Qué archivo o carpeta? Arrástralo a la ventana o elígelo.")
        }
        let choices = inventory.files
            .filter { kind == .other ? $0.kind != .archive : $0.kind == kind }
            .prefix(6).map(\.path)
        var reply = AssistantReply(explanation: explanation, proposals: [])
        reply.extras.fileRequest = FileRequest(kind: kind, choices: Array(choices))
        if let suggestion = upgradeSuggestion(for: step.action, inventory: inventory) {
            reply.extras.suggestions = [suggestion]
        }
        return reply
    }

    /// Nothing built-in fits: recommend a well-known tool, installing it if needed.
    static func recommend(_ tool: CatalogTool, inventory: ToolInventory) -> AssistantReply {
        if isInstalled(tool, inventory: inventory) {
            var reply = AssistantReply(
                explanation: String(localized: "Para eso sirve \(tool.title), que ya tienes: \(tool.detail.lowercasedFirst) Se usa así; edítalo con tus datos:"),
                proposals: []
            )
            reply.extras.template = tool.example ?? "\(tool.command) --help"
            return reply
        }
        let explanation = String(localized: "Para eso sirve \(tool.title): \(tool.detail.lowercasedFirst) No la tienes; puedo instalarla con Homebrew.")
        return AssistantReply(
            explanation: explanation,
            proposals: [AssistantProposal(command: tool.installCommand, tool: "Homebrew",
                                          missingPackage: inventory.has("brew") ? nil : "Homebrew")]
        )
    }

    /// A more capable tool to mention when it isn't installed yet.
    private static func upgradeSuggestion(for action: AssistantAction, inventory: ToolInventory) -> ToolSuggestion? {
        guard let tool = ToolCatalog.upgrade(for: action), !inventory.has(tool.command) else { return nil }
        return ToolSuggestion(tool, isInstalled: false)
    }

    private static func q(_ value: String) -> String { ShellEscape.quote(value) }

    private static func command(for step: AssistantStep, inventory: ToolInventory) -> (String, AssistantProposal)? {
        switch step.action {
        case .runScript:
            guard let script = step.script else { return nil }
            if inventory.scripts.contains(script) {
                let manager = (inventory.packageManager ?? .npm).rawValue
                let command = "\(manager) run \(q(script))"
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

        case .convertToPDF:
            guard let file = step.file, let export = DocumentExport.command(for: file, in: inventory.directory) else { return nil }
            let name = (file as NSString).lastPathComponent
            guard step.compress == true else {
                return (String(localized: "Voy a exportar “\(name)” a PDF con \(export.app). La primera vez, macOS te pedirá permiso para que Comando use \(export.app)."),
                        AssistantProposal(command: export.command, tool: "\(export.app) · incluida en tu Mac"))
            }
            let compressed = derivedName(export.output, suffix: "comprimido", extension: "pdf")
            return (String(localized: "Voy a exportar “\(name)” a PDF con \(export.app) y luego reducir su peso. La primera vez, macOS te pedirá permiso para que Comando use \(export.app)."),
                    AssistantProposal(command: "\(export.command) && \(BuiltInTools.compressPDF) \(q(export.output)) \(q(compressed))",
                                      tool: "\(export.app) y \(BuiltInTools.compressPDF) · incluidas en tu Mac"))

        case .compressPDF:
            guard let file = step.file else { return nil }
            let output = derivedName(file, suffix: "comprimido", extension: "pdf")
            return (String(localized: "Voy a reducir el peso de “\((file as NSString).lastPathComponent)” con el filtro de macOS y te diré cuánto bajó."),
                    AssistantProposal(command: "\(BuiltInTools.compressPDF) \(q(file)) \(q(output))", tool: "\(BuiltInTools.compressPDF) · incluida en Comando"))

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
                let command = ToolCatalog.tool(named: package)?.command ?? package
                let check = inventory.has(command) ? "which \(q(command)) && \(q(command)) --version" : "brew info \(q(package))"
                return (String(localized: "“\(package)” ya está instalado; voy a mostrar dónde está y su versión."),
                        AssistantProposal(command: check, tool: "\(package) · \(inventory.source(of: command))"))
            }
            guard inventory.has("brew") else { return nil }
            let catalog = ToolCatalog.tool(named: package)
            let what = catalog.map { " " + $0.detail } ?? ""
            return (String(localized: "Voy a instalar “\(package)” con Homebrew.") + what,
                    AssistantProposal(command: catalog?.installCommand ?? "brew install \(q(package))", tool: "Homebrew"))

        case .unknown:
            return nil
        }
    }

    /// “Entrevista.wav” → “Entrevista-comprimido.m4a”, next to the original.
    static func derivedName(_ file: String, suffix: String, extension ext: String) -> String {
        let base = (file as NSString).deletingPathExtension
        return "\(base)-\(suffix).\(ext)"
    }

    /// A recipe that matches, filled with what the request says (“llamada
    /// Fotos”, “la palabra TODO”, “el puerto 3000”).
    static func useRecipe(_ recipe: Recipe, request: String, inventory: ToolInventory) -> AssistantReply {
        var values: [String: String] = [:]
        if let text = requestedText(in: request), let parameter = recipe.parameters.first(where: { $0.kind == .text }) {
            values[parameter.id] = text
        }
        if let parameter = recipe.parameters.first(where: { $0.kind == .number }),
           let number = request.firstMatch(of: /\b(\d{1,6})\b/) {
            values[parameter.id] = String(number.1)
        }
        let words = normalized(request)
        for parameter in recipe.parameters where values[parameter.id] == nil && (parameter.kind == .file || parameter.kind == .folder) {
            if let file = inventory.files.first(where: { mentionsFile($0, in: words) }) { values[parameter.id] = file.path }
        }
        let command = recipe.command(with: values)
        let tool = String(command.prefix { $0 != " " })
        var explanation = String(localized: "Voy a \(recipe.title.lowercasedFirst).")
        if let example = recipe.parameters.first(where: { values[$0.id] == nil && $0.defaultValue == nil }) {
            explanation += " " + String(localized: "Puse “\(example.placeholder)” de ejemplo; cámbialo con Editar si quieres otro.")
        }
        return AssistantReply(
            explanation: explanation,
            proposals: [AssistantProposal(command: command, tool: "\(tool) · \(inventory.source(of: tool))")]
        )
    }

    /// The name or text a request gives: “llamada Fotos 2026”, “la palabra
    /// TODO”, or anything in quotes.
    static func requestedText(in request: String) -> String? {
        let quoted = /["“'«]([^"”'»]+)["”'»]/
        let named = /(?i)(?:llamad[oa]|que se llame|con el nombre(?: de)?|de nombre|named|called)\s+([^?.!,]+)/
        // “la palabra TODO en el proyecto” → “TODO”.
        let text = /(?i)(?:la palabra|el texto|la frase)\s+(\S+(?:\s+\S+)*?)(?:\s+(?:en|dentro de|del|de la)\s+.*)?[?.!]?$/
        let found = request.firstMatch(of: quoted).map { String($0.1) }
            ?? request.firstMatch(of: named).map { String($0.1) }
            ?? request.firstMatch(of: text).map { String($0.1) }
        let value = found?.trimmingCharacters(in: .whitespaces)
        return value?.isEmpty == false ? value : nil
    }

    /// Requests to try, picked for what this folder has.
    static func examples(for inventory: ToolInventory) -> [String] {
        var examples: [String] = []
        if let script = ["dev", "start", "storybook"].first(where: inventory.scripts.contains) {
            examples.append(script == "storybook"
                ? String(localized: "Corre storybook")
                : String(localized: "Corre el servidor de desarrollo"))
        }
        if let git = inventory.git, git.changes > 0 {
            examples.append(String(localized: "Sube mis cambios a GitHub"))
        }
        if inventory.files.contains(where: { $0.kind == .audio || $0.kind == .video }) {
            examples.append(String(localized: "Comprime un audio"))
        }
        examples += [
            String(localized: "¿Qué ocupa espacio en esta carpeta?"),
            String(localized: "Crea una carpeta llamada Proyectos"),
            String(localized: "Descarga un video de YouTube"),
            String(localized: "Comprime un audio"),
        ]
        var seen = Set<String>()
        return examples.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }

    /// The recipe that clearly matches by words alone (used without the model).
    static func bestRecipe(for request: String) -> Recipe? {
        let words = normalized(request)
        // Two shared words, or every word of a short request (“¿cuál es mi ip?”).
        let needed = min(2, max(1, keywords(in: words).count))
        let scored = RecipeBook.all.map { ($0, overlap(words, $0)) }
        return scored.filter { $0.1 >= needed }.max { $0.1 < $1.1 }?.0
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }
}

extension AssistantStep {
    /// Actions that work on a file the person has to point at.
    nonisolated var needsFile: Bool {
        [.compressAudio, .compressVideo, .resizeImage, .zipFiles, .convertToPDF, .compressPDF].contains(action)
    }
}

extension String {
    nonisolated var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
