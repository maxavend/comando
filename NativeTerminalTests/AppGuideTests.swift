import Foundation
import Testing
@testable import NativeTerminal

@Suite struct AppGuideTests {
    @Test(arguments: [
        "¿Qué hace?", "¿para qué sirve?", "Para qué sirve esta app", "¿Cuál es el propósito?", "¿Qué puedes hacer?",
        "¿Qué puede hacer Comando?", "¿Cómo funciona?", "¿Cómo se usa?", "Hola, ¿qué eres?", "ayuda", "tutorial",
        "instrucciones", "¿Qué es esto?", "¿Cómo empiezo?", "¿Qué es Comando?", "¿Qué hace esta terminal?",
    ])
    func questionsAboutTheAppGetTheOverview(_ request: String) {
        #expect(AppGuide.topic(for: request) == .overview)
    }

    @Test func questionsAboutAPartGetThatPart() {
        #expect(AppGuide.topic(for: "¿Cómo funciona el asistente?") == .assistant)
        #expect(AppGuide.topic(for: "¿qué es apple intelligence?") == .assistant)
        #expect(AppGuide.topic(for: "¿Cómo cambio de carpeta?") == .folders)
        #expect(AppGuide.topic(for: "¿Para qué son las sesiones?") == .sessions)
        #expect(AppGuide.topic(for: "¿Qué atajos hay?") == .shortcuts)
        #expect(AppGuide.topic(for: "atajos de teclado") == .shortcuts)
        #expect(AppGuide.topic(for: "¿Es privado?") == .privacy)
        #expect(AppGuide.topic(for: "¿Cómo gestiono mis herramientas?") == .tools)
        #expect(AppGuide.topic(for: "¿Cómo escribo comandos?") == .commands)
    }

    @Test(arguments: [
        "¿Para qué sirve git?", "¿Qué es npm?", "¿qué hace ls -la?", "instala ffmpeg", "¿Cómo comprimo un video?",
        "muéstrame mis carpetas", "¿qué carpetas pesan más?", "crea una carpeta llamada Proyectos", "hola",
        "gracias", "¿cómo instalo yt-dlp?", "¿es seguro borrar node_modules?", "¿cómo salgo de vim?", "¿qué hora es?",
    ])
    func otherRequestsAreLeftAlone(_ request: String) {
        #expect(AppGuide.topic(for: request) == nil)
    }

    @Test func everyTopicHasAnAnswerAndFollowUps() {
        let inventory = ToolInventory(directory: "/Users/demo", executables: [])
        for topic in AppGuide.Topic.allCases {
            let reply = AppGuide.reply(for: topic, inventory: inventory)
            #expect(!reply.explanation.isEmpty)
            #expect(reply.extras.guide.count >= 4)
            #expect(!reply.extras.examples.isEmpty)
            #expect(reply.proposals.isEmpty)
            // Follow-up questions lead back to the guide.
            if topic != .assistant {
                #expect(reply.extras.examples.allSatisfy { AppGuide.topic(for: $0) != nil })
            }
        }
    }

    @Test func guideWordsGoToTheAssistant() {
        let known: Set<String> = ["ls", "git"]
        #expect(IntentDetector.isPlainLanguage("ayuda", knownCommands: known))
        #expect(IntentDetector.isPlainLanguage("tutorial", knownCommands: known))
        #expect(IntentDetector.isPlainLanguage("¿Qué hace?", knownCommands: known))
        #expect(!IntentDetector.isPlainLanguage("help", knownCommands: ["help"]))
    }

    @Test func guideAnswersWithoutTheModel() async {
        let inventory = ToolInventory(directory: "/Users/demo", executables: [])
        let reply = await AssistantEngine.reply(to: "¿para qué sirve?", inventory: inventory)
        #expect(reply.error == nil)
        #expect(reply.explanation.hasPrefix("Comando es una terminal"))
    }

    @Test func savedRepliesWithoutAGuideStillLoad() throws {
        let old = #"{"examples":["a"],"suggestions":[]}"#
        let extras = try JSONDecoder().decode(AssistantExtras.self, from: Data(old.utf8))
        #expect(extras.guide.isEmpty)
        let round = try JSONDecoder().decode(AssistantExtras.self, from: JSONEncoder().encode(AppGuide.reply(for: .overview, inventory: ToolInventory(directory: "/", executables: [])).extras))
        #expect(round.guide.count == 5)
    }
}
