import Foundation
import Testing
@testable import NativeTerminal

@Suite struct AssistantConversationTests {
    private func folder(with names: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "rn-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in names { try Data().write(to: url.appending(path: name)) }
        return url
    }

    private func inventory(_ url: URL) -> ToolInventory {
        var inventory = ToolInventory(directory: url.path(percentEncoded: false), executables: [])
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
        inventory.files = names.map { name in
            let ext = (name as NSString).pathExtension.lowercased()
            let kind: ToolInventory.FileInfo.Kind = ["jpg", "png", "heic"].contains(ext) ? .image : ext == "pdf" ? .pdf : .other
            return .init(name: name, path: url.appending(path: name).path(percentEncoded: false), kind: kind, size: 0)
        }
        return inventory
    }

    @Test func renamesPhotosSafelyWithAPreview() throws {
        let url = try folder(with: ["IMG_002.jpg", "IMG_001.jpg", "IMG_003.jpg", "notas.pdf"])
        let reply = try #require(AssistantEngine.renameReply(for: "Renombra todas las fotos como vacaciones", inventory: inventory(url)))
        let command = try #require(reply.proposals.first?.command)
        #expect(command == #"n=1; for f in *.jpg(N); do mv -n -- "$f" "vacaciones-$n.jpg"; ((n++)); done"#)
        #expect(command.contains("mv -n"), "Nunca reemplaza archivos")
        // The brake: it asks first, showing exactly what changes.
        #expect(DangerDetector.risk(of: command) != nil)
        let plan = try #require(RenamePlan(command: command))
        let preview = plan.preview(in: url.path(percentEncoded: false))
        #expect(preview.contains("3 archivos .jpg"))
        #expect(preview.contains("IMG_001.jpg → vacaciones-1.jpg"))
        #expect(!preview.contains("notas.pdf"))
    }

    @Test func renameNamesAreSafeInTheCommand() {
        #expect(RenamePlan.cleanBase("Viaje a Chiloé 2026") == "viaje-a-chiloe-2026")
        #expect(RenamePlan.cleanBase("x\"; rm -rf ~; \"") == "x-rm-rf")
        #expect(RenamePlan(command: "rm -rf *") == nil)
    }

    @Test func otherMassMovesAlsoAsk() {
        #expect(DangerDetector.risk(of: "for f in *.png; do mv \"$f\" \"img-$f\"; done") != nil)
        #expect(DangerDetector.risk(of: #"find . -name '*.txt' -exec mv {} archivo/ \;"#) != nil)
        #expect(DangerDetector.risk(of: "autoload -U zmv; zmv '(*).txt' '$1.md'") != nil)
        #expect(DangerDetector.risk(of: "zmv -n '(*).txt' '$1.md'") == nil, "La vista previa no cambia nada")
        #expect(DangerDetector.risk(of: "mv notas.txt apuntes.txt") == nil)
    }

    @Test func spokenTextIsCheckedBeforeShowing() {
        let plain = AssistantReply(explanation: "", proposals: [])
        let withCommand = AssistantReply(explanation: "", proposals: [AssistantProposal(command: "ls", tool: "ls")])
        #expect(AssistantEngine.vetted("Puedes usar `tar -czf respaldo.tgz carpeta` para empaquetar.", reply: plain) != nil)
        #expect(AssistantEngine.vetted("Prueba con `sudo rm -rf /`", reply: plain) == nil)
        #expect(AssistantEngine.vetted("Bórralo con rm -rf carpeta", reply: plain) == nil)
        #expect(AssistantEngine.vetted("¡Listo, ya lo hice! Quedó comprimido.", reply: withCommand) == nil)
        let cut = AssistantEngine.vetted("Voy a reducir el audio.\n\n**Comando**:\n\n- Herramientas para audio.", reply: plain)
        #expect(cut == "Voy a reducir el audio.")
    }

    @Test func followUpsAreNoticed() {
        #expect(AssistantConversation.mayDependOnContext("ahora pásalo a mp3"))
        #expect(AssistantConversation.mayDependOnContext("¿y eso qué hace?"))
        #expect(!AssistantConversation.mayDependOnContext("Descarga el video de YouTube que está en mis notas y conviértelo"))
        #expect(!AssistantConversation.mayDependOnContext("comprime el audio Entrevista.aiff"))
    }

    @Test func questionsAboutCommandsAreAnswered() {
        #expect(AssistantEngine.asksForMeaning(AssistantEngine.normalized("¿Qué hace el comando tar?")))
        #expect(AssistantEngine.asksForMeaning(AssistantEngine.normalized("¿Cómo funciona git rebase?")))
    }

    @Test func mp3UsesFfmpeg() async throws {
        let url = try folder(with: ["Entrevista.aiff"])
        var inventory = inventory(url)
        inventory.files = [.init(name: "Entrevista.aiff", path: url.appending(path: "Entrevista.aiff").path(percentEncoded: false), kind: .audio, size: 10)]
        inventory.executables = ["ffmpeg", "afconvert"]
        let reply = await AssistantEngine.plainReply(to: "Convierte Entrevista.aiff a mp3", inventory: inventory)
        let command = try #require(reply.proposals.first?.command)
        #expect(command.hasPrefix("ffmpeg -n -i ") && command.contains("libmp3lame") && command.hasSuffix("Entrevista.mp3"), "\(command)")
    }

    @Test func madeUpFilesAreNotShown() throws {
        let url = try folder(with: ["IMG_0412.jpg"])
        let reply = AssistantReply(explanation: "", proposals: [AssistantProposal(command: "ls", tool: "ls")])
        #expect(AssistantEngine.vetted("Renombraré IMG_0412.jpg.", reply: reply, inventory: inventory(url)) != nil)
        #expect(AssistantEngine.vetted("Renombraré fotos1.jpg y fotos2.jpg.", reply: reply, inventory: inventory(url)) == nil)
        let long = AssistantEngine.vetted("Cambia los nombres.\n\n**Lista**\n• a", reply: reply, inventory: inventory(url))
        #expect(long == "Cambia los nombres.")
    }

    @Test func ideasAreNotRepeatedAsAList() {
        var reply = AssistantReply(explanation: "", proposals: [])
        reply.extras.examples = ["¿Qué ocupa espacio en esta carpeta?", "Descarga un video de YouTube"]
        let text = AssistantEngine.vetted("De nada, aquí estoy. Aquí tienes ideas:\n\n• ¿Qué ocupa más espacio en esta carpeta?\n• Descargar un video de YouTube.\n\n¿Cuál te interesa?", reply: reply)
        #expect(text == "De nada, aquí estoy. ¿Cuál te interesa?" || text?.contains("YouTube") == false, "\(text ?? "nil")")
    }

    @Test func theCommandIsNotCopiedIntoTheText() {
        let reply = AssistantReply(explanation: "", proposals: [AssistantProposal(command: "afconvert -f m4af a.aiff b.m4a", tool: "afconvert")])
        let text = AssistantEngine.vetted("El comando \"afconvert -f m4af a.aiff b.m4a\" lo deja más liviano.", reply: reply)
        #expect(text == "Este comando lo deja más liviano.")
    }
}
