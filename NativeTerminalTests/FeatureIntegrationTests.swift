import Foundation
import SwiftData
import Testing
@testable import NativeTerminal

/// Exercises each feature through the same code the buttons call — the real
/// controller, SwiftData and zsh — without moving the mouse.
@MainActor
@Suite(.serialized)
final class FeatureIntegrationTests {
    private let container: ModelContainer
    private let controller: TerminalController
    private let folder: URL
    private var folderPath: String { folder.path(percentEncoded: false) }

    init() throws {
        container = try ModelContainer(
            for: TerminalSession.self, CommandEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        controller = TerminalController(modelContext: container.mainContext)
        folder = FileManager.default.temporaryDirectory
            .appending(path: "nt-it-\(UUID().uuidString.prefix(6))")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder.appending(path: "Carpeta Uno"), withIntermediateDirectories: true)
        try "hola".write(to: folder.appending(path: "notas.txt"), atomically: true, encoding: .utf8)
    }

    isolated deinit {
        controller.terminateAll()
        for shell in controller.shells.values { shell.delegate = nil }
    }

    // MARK: - Helpers

    private func makeSession() async throws -> (TerminalSession, ShellSession) {
        let session = controller.createSession(directory: folderPath)
        let shell = controller.shell(for: session)
        try await waitUntil("el shell está listo") { shell.phase == .idle }
        return (session, shell)
    }

    private func entries(of session: TerminalSession) -> [CommandEntry] {
        session.entries.sorted { $0.startedAt < $1.startedAt }
    }

    private func runAndWait(_ command: String, in session: TerminalSession, confirmed: Bool = false) async throws -> CommandEntry {
        let before = session.entries.count
        controller.submit(command, in: session, confirmed: confirmed)
        try await waitUntil("se crea la entrada de “\(command)”") { session.entries.count > before }
        let entry = entries(of: session).last!
        try await waitUntil("termina “\(command)”") { entry.isFinished }
        return entry
    }

    private func waitUntil(_ what: String, timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Se agotó el tiempo esperando: \(what)")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    // MARK: - 2. Recetas

    @Test func recipeRunsInChat() async throws {
        let (session, _) = try await makeSession()
        let recipe = try #require(RecipeBook.all.first { $0.id == "mkdir" })
        let command = recipe.command(with: ["name": "Desde Receta"])
        let entry = try await runAndWait(command, in: session)
        #expect(entry.succeeded)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Desde Receta").path(percentEncoded: false)))
    }

    // MARK: - 1. Procesos activos

    @Test func serverIsDetectedAndStoppedFromSidebar() async throws {
        let (session, shell) = try await makeSession()
        controller.submit("printf 'Ready\\n- Local: http://localhost:6006/\\n'; sleep 30", in: session)
        try await waitUntil("se detecta el servidor local") { shell.live?.localURL != nil }
        #expect(shell.live?.localURL?.absoluteString == "http://localhost:6006/")
        #expect(shell.isBusy)

        // The sidebar's stop button calls interrupt().
        shell.interrupt()
        let entry = try #require(entries(of: session).last)
        try await waitUntil("se detiene el comando") { entry.isFinished }
        #expect(entry.wasStopped)
        #expect(!entry.plainOutput.contains("^C"), "Quedó el eco ^C en la salida")
    }

    // MARK: - 3. Explicación por partes

    @Test func everyRunCommandCanBeExplained() async throws {
        let (session, _) = try await makeSession()
        let entry = try await runAndWait("ls -lhG Carpeta\\ Uno", in: session)
        let parts = CommandExplainer.parts(of: entry.command)
        #expect(parts.map(\.token) == ["ls", "-lhG", "Carpeta\\ Uno"])
        #expect(parts[1].explanation.contains("en detalle"))
        #expect(CommandGlossary.describe(entry.command) == "Listar archivos")
    }

    // MARK: - 4. Papelera

    @Test func rmOffersTrashAndMovesFileThere() async throws {
        let (session, _) = try await makeSession()
        let file = folder.appending(path: "borrar-me.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        controller.submit("rm borrar-me.txt", in: session)
        let pending = try #require(controller.pendingCommand, "rm no pidió confirmación")
        #expect(pending.trashAlternative == "trash borrar-me.txt")
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)), "Se borró antes de confirmar")

        controller.moveToTrashInstead()
        try await waitUntil("el archivo sale de la carpeta") {
            !FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        }
        let entry = try #require(entries(of: session).last)
        try await waitUntil("termina trash") { entry.isFinished }
        #expect(entry.command == "trash borrar-me.txt")
        #expect(entry.succeeded)
    }

    @Test func cancellingRiskyCommandRunsNothing() async throws {
        let (session, _) = try await makeSession()
        controller.submit("rm -rf Carpeta\\ Uno", in: session)
        #expect(controller.pendingCommand?.risk.title.contains("borra") == true)
        controller.pendingCommand = nil // “Cancelar”
        try await Task.sleep(for: .milliseconds(500))
        #expect(session.entries.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Carpeta Uno").path(percentEncoded: false)))
    }

    // MARK: - 5. Git

    @Test func gitStateIsRead() async throws {
        let (session, _) = try await makeSession()
        _ = try await runAndWait("git init -q && git checkout -q -b prueba && echo hola > nuevo.txt", in: session)
        let info = try #require(await GitInfo.read(in: folderPath), "No se leyó el repositorio")
        #expect(info.branch == "prueba")
        #expect(info.changes == 2) // notas.txt y nuevo.txt; Git no cuenta carpetas vacías
        #expect(await GitInfo.read(in: NSTemporaryDirectory()) == nil)
    }

    // MARK: - 6. Progreso

    @Test func progressLineIsDetectedWhileRunning() async throws {
        let (session, shell) = try await makeSession()
        controller.submit(#"for i in $(seq 0 10 100); do printf "\rDescargando [%d%%]" $i; sleep 0.15; done; echo"#, in: session)
        var seen: [Double] = []
        try await waitUntil("aparece el progreso") {
            guard let live = shell.live,
                  let line = live.buffer.lines.last(where: { $0.contains { $0.character != " " } }),
                  let progress = ProgressParser.parse(String(line.map(\.character))) else { return false }
            seen.append(progress.fraction)
            return progress.fraction > 0
        }
        #expect(!seen.isEmpty)
        try await waitUntil("termina") { !shell.isBusy }
    }

    // MARK: - 7. Salidas largas

    @Test func longOutputFoldsToLastLines() async throws {
        let (session, _) = try await makeSession()
        let entry = try await runAndWait("seq 1 80", in: session)
        let rendered = try #require(RenderCache.shared.immediate(for: entry))
        #expect(rendered.totalLines == 80)
        #expect(String(rendered.preview.lastLines(10).characters) == (71...80).map(String.init).joined(separator: "\n"))
    }

    // MARK: - Archivos y enlaces clicables

    @Test func lsOutputLinksFilesAndURLs() async throws {
        let (session, _) = try await makeSession()
        let entry = try await runAndWait("ls", in: session)
        let rendered = try #require(RenderCache.shared.immediate(for: entry))
        let links = rendered.preview.runs.compactMap(\.link).map(\.lastPathComponent)
        #expect(links.contains("notas.txt"))
        #expect(links.contains("Carpeta Uno"))

        let web = try await runAndWait("echo 'Abre http://localhost:3000/ ahora'", in: session)
        let webLinks = try #require(RenderCache.shared.immediate(for: web)).preview.runs.compactMap(\.link)
        #expect(webLinks.map(\.absoluteString) == ["http://localhost:3000/"])
    }

    @Test func clickingAFolderNavigates() async throws {
        let (session, shell) = try await makeSession()
        // A click on a folder link calls navigate(to:in:), which runs a visible cd.
        controller.navigate(to: folder.appending(path: "Carpeta Uno").path(percentEncoded: false), in: session)
        try await waitUntil("cambia de carpeta") { shell.directory.hasSuffix("Carpeta Uno") }
        let entry = try #require(entries(of: session).last)
        try await waitUntil("se registra la nueva carpeta") { entry.movedTo != nil }
        #expect(entry.command.hasPrefix("cd "))
    }

    // MARK: - 8. Sesiones con identidad

    @Test func pinningAndAppearancePersist() throws {
        let session = controller.createSession(directory: folderPath)
        session.isPinned = true
        session.emoji = "🚀"
        session.colorIndex = 1
        try container.mainContext.save()
        let id = session.id
        let fetched = try #require(try container.mainContext.fetch(
            FetchDescriptor<TerminalSession>(predicate: #Predicate { $0.id == id })
        ).first)
        #expect(fetched.isPinned)
        #expect(fetched.emoji == "🚀")
        #expect(SessionColor.color(at: fetched.colorIndex) == .blue)
    }
}
