import Foundation
import FoundationModels

/// Apple Intelligence as a conversation, one per session: it remembers what
/// was said, speaks in its own words, and can look at the folder, what's
/// installed, command examples and tools. What to run is still decided by
/// `AssistantEngine` with its checks; this only says it, naturally.
@MainActor
final class AssistantConversation {
    let context = AssistantContext()
    private var session: LanguageModelSession
    /// The last exchanges, to resume after the model's memory fills up.
    private var recent: [(request: String, reply: String)] = []
    private var turns = 0
    private(set) var isSpeaking = false

    init(history: [(request: String, reply: String)] = []) {
        recent = Array(history.suffix(3))
        session = Self.makeSession(context: context, history: recent)
    }

    static let persona = """
    Eres el asistente de Comando, una terminal para macOS con forma de chat. Hablas en español, \
    cercano y natural, como una persona que sabe mucho de la terminal y lo explica simple, sin tecnicismos innecesarios. \
    Responde breve: una a tres oraciones, salvo que te pidan explicar algo; entonces explica claro y ordenado. \
    Varía tus palabras: no repitas frases hechas ni empieces siempre igual. \
    Comando muestra aparte, en tarjetas, lo que preparó (comandos, archivos, herramientas): \
    descríbelo con tus palabras, sin copiar el comando completo y sin inventar otros. \
    Nada se ejecuta hasta que la persona presiona Ejecutar: nunca digas que ya hiciste algo. \
    Nunca sugieras sudo ni borrar con rm; para borrar, Comando usa la Papelera. \
    Si te falta información, pregunta. Usa tus herramientas para ver archivos, lo instalado, \
    ejemplos de un comando o buscar herramientas, en vez de adivinar. \
    Cuando muestres un comando al explicar, ponlo entre comillas invertidas. \
    Escribe solo tu mensaje: sin títulos, sin etiquetas como "Comando:" y sin repetir el contexto que te da Comando. \
    Puedes usar **negrita** para lo importante y listas cortas cuando expliques pasos.
    """

    private static func makeSession(context: AssistantContext, history: [(request: String, reply: String)]) -> LanguageModelSession {
        var instructions = persona
        if !history.isEmpty {
            instructions += "\n\nConversación reciente:\n" + history.map {
                "- La persona: \($0.request)\n  Tú: \($0.reply.prefix(240))"
            }.joined(separator: "\n")
        }
        let tools: [any Tool] = [
            FolderFilesTool(context: context), InstalledTool(context: context),
            CommandExamplesTool(), ToolSearchTool(context: context),
        ]
        return LanguageModelSession(tools: tools, instructions: instructions)
    }

    // MARK: - Follow-ups

    /// “Ahora en mp3” after “comprime Entrevista.aiff”: the request on its
    /// own, so the rest of the assistant understands it. Unchanged when it
    /// already stands alone or there's nothing before it.
    func standalone(_ request: String, inventory: ToolInventory? = nil) async -> String {
        let words = AssistantEngine.normalized(request)
        // Thanks, greetings and questions about the app never continue a request.
        guard let last = recent.last, Self.mayDependOnContext(request), !AssistantEngine.isThanks(words),
              !AssistantEngine.isGreeting(words), AppGuide.topic(for: request) == nil else { return request }
        // It names a file of this folder: it stands on its own.
        if let inventory, inventory.files.contains(where: { request.localizedCaseInsensitiveContains($0.name) }) { return request }
        let rewritten = await rewrite(request, after: last)
        // The model kept it as it was: carry over a file the last request named.
        if rewritten == request, let inventory,
           let file = inventory.files.first(where: { last.request.localizedCaseInsensitiveContains($0.name) }),
           !inventory.files.contains(where: { request.localizedCaseInsensitiveContains($0.name) }) {
            return request + " (" + file.name + ")"
        }
        return rewritten
    }

    private func rewrite(_ request: String, after last: (request: String, reply: String)) async -> String {
        let prompt = """
        Antes la persona pidió: \(last.request)
        Respondiste: \(last.reply.prefix(300))
        Ahora dice: \(request)
        """
        let rewritten = await AssistantEngine.firstResult(within: .seconds(4)) {
            let session = LanguageModelSession(instructions: """
            Reescribes el último mensaje de una persona como un pedido completo y claro, en español, \
            usando lo que se habló antes: nombra el archivo, programa o formato del que habla. \
            Ejemplo: antes "achica foto.png", ahora "y que quede de 800 de ancho" → "Achica foto.png a 800 píxeles de ancho". \
            Si ya se entiende solo, devuélvelo igual. No agregues nada que la persona no haya pedido.
            """)
            let options = GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 60)
            return try? await session.respond(to: prompt, generating: StandaloneRequest.self, options: options).content.request
        }
        guard let text = rewritten?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.count <= request.count * 4 + 80 else { return request }
        return text
    }

    /// Short, or leaning on what came before (“eso”, “ahora”, “también”…).
    nonisolated static func mayDependOnContext(_ request: String) -> Bool {
        let words = " " + AssistantEngine.normalized(request).map { $0.isLetter ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        let markers = [" eso ", " esto ", " ese ", " esa ", " ahora ", " tambien ", " otra vez ", " de nuevo ", " y si ",
                       " igual ", " el mismo ", " la misma ", " mejor ", " en vez ", " ahi ", " alli ", " el otro ", " la otra ",
                       " entonces "]
        return markers.contains { words.contains($0) } || request.split(separator: " ").count <= 3
    }

    // MARK: - Speaking

    /// The reply in the assistant's own words, streamed through `onText`.
    /// Nil when the model can't or shouldn't say it, so the prepared text stays.
    func speak(request: String, reply: AssistantReply, inventory: ToolInventory,
               onText: @escaping (String) -> Void) async -> String? {
        guard AssistantEngine.isAvailable, !AssistantEngine.keepsExactWords(reply) else { return nil }
        context.inventory = inventory
        let prompt = "Mensaje de la persona: \(request)\n" + AssistantEngine.facts(for: reply)
        // With something already prepared there's nothing to look up: it only
        // says what that is. Questions and advice may use the tools.
        let prepared = !reply.proposals.isEmpty || reply.extras.template != nil
            || reply.extras.fileRequest != nil || !reply.extras.guide.isEmpty
        let options = GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9),
            temperature: 0.7,
            maximumResponseTokens: reply.answersItself ? 420 : (prepared ? 110 : 180),
            toolCallingMode: prepared ? .disallowed : .allowed
        )
        // A second message while this one speaks gets a one-off session.
        let speaker = isSpeaking ? Self.makeSession(context: context, history: recent) : session
        isSpeaking = true
        defer { isSpeaking = false }

        var text: String?
        for attempt in 0..<2 {
            do {
                text = try await stream(prompt, options: options, from: speaker, reply: reply, onText: onText)
                break
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                // Memory full: start over with a summary of the last exchanges.
                guard attempt == 0 else { break }
                session = Self.makeSession(context: context, history: recent)
            } catch {
                break
            }
        }
        if let text {
            recent.append((request, text))
            recent = Array(recent.suffix(3))
            turns += 1
            // Keep the model's memory light: refresh it now and then.
            if turns >= 8 {
                turns = 0
                session = Self.makeSession(context: context, history: recent)
            }
        }
        return text
    }

    private enum SpeakError: Error { case unsafe, timedOut }

    /// Streams the answer, checking each piece; stops at the first one that
    /// isn't safe to show, or if the model goes quiet.
    private func stream(_ prompt: String, options: GenerationOptions, from speaker: LanguageModelSession,
                        reply: AssistantReply, onText: @escaping (String) -> Void) async throws -> String? {
        let watchdog = Task {
            try await Task.sleep(for: .seconds(reply.answersItself ? 30 : 15))
            throw SpeakError.timedOut
        }
        defer { watchdog.cancel() }
        var latest = ""
        let started = ContinuousClock.now
        for try await snapshot in speaker.streamResponse(to: prompt, options: options) {
            if watchdog.isCancelled || ContinuousClock.now - started > .seconds(reply.answersItself ? 30 : 15) { break }
            guard let safe = AssistantEngine.vetted(snapshot.content, reply: reply, inventory: context.inventory, request: prompt) else {
                if !latest.isEmpty { return nil }
                continue
            }
            latest = safe
            onText(safe)
        }
        return latest.isEmpty ? nil : latest
    }
}

/// The last message as a complete request.
@Generable
struct StandaloneRequest {
    @Guide(description: "El pedido completo y claro, en español")
    var request: String
}
