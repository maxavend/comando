import Foundation
import Testing
@testable import NativeTerminal

struct ToolExamplesTests {
    @Test func readsATldrPage() {
        let page = """
        # qpdf

        > Versatile PDF transformation software.
        > More information: <https://manned.org/qpdf>.

        - Merge all the pages of multiple PDF files:

        `qpdf --empty --pages {{path/to/file1.pdf file2.pdf}} -- {{path/to/output.pdf}}`
        """
        let examples = ToolKnowledge.parse(page, isSpanish: false)
        #expect(examples.description == "Versatile PDF transformation software.")
        #expect(examples.examples.first?.0 == "Merge all the pages of multiple PDF files")
        #expect(examples.examples.first?.1 == "qpdf --empty --pages path/to/file1.pdf file2.pdf -- path/to/output.pdf")
    }
}

/// Real searches: downloads the catalogs and asks the model. Runs with NATIVETERM_STRESS.
@Suite(.serialized, .enabled(if: AssistantEngine.isAvailable && ProcessInfo.processInfo.environment["NATIVETERM_STRESS"] != nil))
struct ToolDiscoveryTests {
    @Test func findsToolsBeyondTheCatalog() async {
        await ToolKnowledge.shared.prepare()
        let path = (ProcessInfo.processInfo.environment["NATIVETERM_PATH"] ?? "/opt/homebrew/bin:/usr/bin:/bin").split(separator: ":").map(String.init)
        var context = await ToolInventory.gather(directory: NSTemporaryDirectory(), executables: Set(ExecutableIndex.shared.names(for: path)), attachments: [], path: path)
        context.files = [
            .init(name: "informe.pdf", path: "informe.pdf", kind: .pdf, size: 1),
            .init(name: "notas.md", path: "notas.md", kind: .other, size: 1),
            .init(name: "data.json", path: "data.json", kind: .other, size: 1),
            .init(name: "clip.mov", path: "clip.mov", kind: .video, size: 1),
        ]
        AssistantEngine.trace = { print("     · \($0)") }
        for request in [
            "quiero sacarle las páginas 2 y 3 a informe.pdf", "convierte notas.md a pdf", "quiero ver el clima en la terminal",
            "muestra data.json bonito y con colores", "convierte clip.mov en un gif", "quiero ver un árbol de esta carpeta",
            "mide la velocidad de mi internet", "renombra muchos archivos a la vez", "quiero ver los procesos de forma bonita",
        ] {
            let start = ContinuousClock.now
            let reply = await AssistantEngine.reply(to: request, inventory: context)
            let elapsed = ContinuousClock.now - start
            print("FIND ⏱ \(elapsed) «\(request)» → \(reply.error ?? reply.explanation)")
            for proposal in reply.proposals { print("     ⌘ \(proposal.command) | \(proposal.tool) | \(proposal.about ?? "-") | instalar: \(proposal.install ?? "-")") }
            for other in reply.extras.suggestions { print("     ↳ \(other.title) · \(other.origin ?? "") — \(other.detail)") }
            #expect(elapsed < .seconds(30))
            for proposal in reply.proposals { #expect(DangerDetector.risk(of: proposal.command) == nil) }
        }
    }
}
