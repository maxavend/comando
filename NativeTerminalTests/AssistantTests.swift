import Foundation
import Testing
@testable import NativeTerminal

private func inventory(
    scripts: [String] = ["dev", "storybook", "build", "test"],
    executables: Set<String> = ["git", "gh", "npm", "afconvert", "sips", "zip", "brew", "ffmpeg"],
    files: [ToolInventory.FileInfo] = [],
    attachments: [ToolInventory.FileInfo] = [],
    git: GitInfo? = GitInfo(branch: "main", changes: 4),
    hasRemote: Bool = true
) -> ToolInventory {
    var inventory = ToolInventory(directory: "/Users/demo/Proyecto", executables: executables)
    inventory.scripts = scripts
    inventory.packageManager = .npm
    inventory.files = files
    inventory.attachments = attachments
    inventory.git = git
    inventory.gitHasRemote = hasRemote
    return inventory
}

private let audio = ToolInventory.FileInfo(name: "Entrevista Final.wav", path: "/Users/demo/Desktop/Entrevista Final.wav", kind: .audio, size: 48_000_000)
private let logo = ToolInventory.FileInfo(name: "logo.png", path: "logo.png", kind: .image, size: 2_000_000)

struct IntentDetectorTests {
    let known: Set<String> = ["git", "ls", "npm", "open"]

    @Test func commandsStayCommands() {
        #expect(!IntentDetector.isPlainLanguage("git status", knownCommands: known))
        #expect(!IntentDetector.isPlainLanguage("ls -la", knownCommands: known))
        #expect(!IntentDetector.isPlainLanguage("./build.sh release", knownCommands: known))
        #expect(!IntentDetector.isPlainLanguage("cd Documentos", knownCommands: known))
        #expect(!IntentDetector.isPlainLanguage("foo --bar", knownCommands: known))
        #expect(!IntentDetector.isPlainLanguage("htop", knownCommands: known))
        #expect(IntentDetector.isPlainLanguage("Hola", knownCommands: known))
        #expect(IntentDetector.isPlainLanguage("gracias!", knownCommands: known))
    }

    @Test func plainWordsGoToTheAssistant() {
        #expect(IntentDetector.isPlainLanguage("corre el servidor de storybook", knownCommands: known))
        #expect(IntentDetector.isPlainLanguage("sube esto a GitHub", knownCommands: known))
        #expect(IntentDetector.isPlainLanguage("? open the readme", knownCommands: known))
        #expect(IntentDetector.request(from: "? open the readme") == "open the readme")
    }
}

struct AssistantBuilderTests {
    @Test func runScriptUsesTheProjectManager() {
        var step = AssistantStep(action: .runScript)
        step.script = "Storybook"
        let reply = AssistantEngine.build(
            steps: AssistantEngine.validate([step], request: "corre storybook", inventory: inventory()),
            request: "corre storybook", inventory: inventory()
        )
        #expect(reply.proposals.map(\.command) == ["npm run storybook"])
        #expect(reply.proposals.first?.tool == "storybook · script de npm")
    }

    @Test func audioUsesTheSingleAttachment() {
        let context = inventory(attachments: [audio])
        let steps = AssistantEngine.validate([AssistantStep(action: .compressAudio)], request: "comprime esto para whatsapp", inventory: context)
        let reply = AssistantEngine.build(steps: steps, request: "", inventory: context)
        #expect(reply.proposals.first?.command
                == "afconvert -f m4af -d aac -b 64000 '/Users/demo/Desktop/Entrevista Final.wav' '/Users/demo/Desktop/Entrevista Final-comprimido.m4a'")
    }

    @Test func resizeTakesTheWidthFromTheRequest() {
        var step = AssistantStep(action: .resizeImage)
        step.file = "logo"
        let context = inventory(files: [logo])
        let steps = AssistantEngine.validate([step], request: "achica el logo a 800 px", inventory: context)
        let reply = AssistantEngine.build(steps: steps, request: "", inventory: context)
        #expect(reply.proposals.first?.command == "sips --resampleWidth 800 logo.png --out logo-800px.png")
    }

    @Test func gitPublishDependsOnTheRepository() {
        var step = AssistantStep(action: .gitPublish)
        step.message = "Nuevo botón"
        let withRemote = AssistantEngine.build(steps: [step], request: "", inventory: inventory())
        #expect(withRemote.proposals.first?.command == "git add -A && git commit -m 'Nuevo botón' && git push")

        let noRepo = AssistantEngine.build(steps: [step], request: "", inventory: inventory(git: nil))
        #expect(noRepo.proposals.first?.command.hasSuffix("gh repo create Proyecto --private --source=. --push") == true)

        let noGh = AssistantEngine.build(steps: [step], request: "", inventory: inventory(executables: ["git"], git: nil))
        #expect(noGh.proposals.first?.missingPackage == "gh")
    }

    @Test func videoPrefersFfmpegThenAvconvert() {
        let video = ToolInventory.FileInfo(name: "demo.mov", path: "demo.mov", kind: .video, size: 1)
        let step = AssistantStep(action: .compressVideo, file: "demo.mov")
        let ffmpeg = AssistantEngine.build(steps: [step], request: "", inventory: inventory(files: [video]))
        #expect(ffmpeg.proposals.first?.command.hasPrefix("ffmpeg -i demo.mov") == true)
        let builtIn = AssistantEngine.build(steps: [step], request: "", inventory: inventory(executables: ["git"], files: [video]))
        #expect(builtIn.proposals.first?.command == "avconvert --preset Preset1280x720 --source demo.mov --output demo-720p.mov")
    }

    @Test func guessesWithoutSupportAreDropped() {
        let request = "hazme un sandwich"
        let steps = AssistantEngine.validate(
            [AssistantStep(action: .gitStatus), AssistantStep(action: .compressAudio, file: "Entrevista Final.wav")],
            request: request, inventory: inventory()
        )
        #expect(steps.isEmpty)
        #expect(AssistantEngine.build(steps: steps, request: request, inventory: inventory()).error != nil)
    }

    @Test func asksForTheFileInsteadOfGivingUp() {
        let request = "Hola, quisiera comprimir un audio, ¿cómo puedo hacer?"
        let song = ToolInventory.FileInfo(name: "cancion.wav", path: "cancion.wav", kind: .audio, size: 1)
        let context = inventory(executables: ["afconvert"], files: [logo, song])
        // Even if the model finds nothing, the words are enough.
        let steps = AssistantEngine.validate([AssistantStep(action: .unknown)], request: request, inventory: context)
        #expect(steps.map(\.action) == [.compressAudio])
        let reply = AssistantEngine.build(steps: steps, request: request, inventory: context)
        #expect(reply.error == nil)
        #expect(reply.proposals.isEmpty)
        #expect(reply.extras.fileRequest == FileRequest(kind: .audio, choices: ["cancion.wav"]))
        #expect(reply.extras.suggestions.map(\.package) == ["ffmpeg"])
    }

    @Test func folderFilesNeedToBeNamed() {
        let song = ToolInventory.FileInfo(name: "Glass.aiff", path: "Glass.aiff", kind: .audio, size: 1)
        let context = inventory(files: [song])
        let unnamed = AssistantEngine.validate([AssistantStep(action: .compressAudio, file: "Glass.aiff")], request: "comprime un audio", inventory: context)
        #expect(unnamed.first?.file == nil)
        let named = AssistantEngine.validate([AssistantStep(action: .compressAudio, file: "Glass.aiff")], request: "comprime el audio glass", inventory: context)
        #expect(named.first?.file == "Glass.aiff")
    }

    @Test func compressingAnAudioIsNotAZip() {
        let steps = AssistantEngine.validate([AssistantStep(action: .zipFiles)], request: "comprime este audio", inventory: inventory(attachments: [audio]))
        #expect(steps.map(\.action) == [.compressAudio])
        #expect(steps.first?.file == audio.path)
    }

    @Test func recommendsAToolToInstall() {
        let reply = AssistantEngine.build(steps: [], request: "quiero descargar un video de youtube", inventory: inventory())
        #expect(reply.proposals.map(\.command) == ["brew install yt-dlp"])
        #expect(reply.explanation.contains("yt-dlp"))

        let installed = AssistantEngine.build(steps: [], request: "quiero descargar un video de youtube",
                                              inventory: inventory(executables: ["yt-dlp", "brew"]))
        // Already installed: how to use it, to complete before running.
        #expect(installed.proposals.isEmpty)
        #expect(installed.extras.template == "yt-dlp 'https://youtu.be/…'")
        #expect(installed.explanation.contains("ya tienes"))
    }

    @Test func installUsesTheCatalogPackageName() {
        let step = AssistantEngine.validate([AssistantStep(action: .installTool, package: "magick")], request: "instala magick", inventory: inventory())
        #expect(step.first?.package == "imagemagick")
    }

    @Test func packageCommandsRefreshTheToolLists() {
        #expect(TerminalController.changesInstalledTools("brew install ffmpeg"))
        #expect(TerminalController.changesInstalledTools("cd x && npm uninstall -g foo"))
        #expect(!TerminalController.changesInstalledTools("brew info ffmpeg"))
        #expect(!TerminalController.changesInstalledTools("ls install"))
    }

    @Test func smallTalkIsAnsweredWithoutTheModel() {
        #expect(AssistantEngine.smallTalkReply(to: AssistantEngine.normalized("Hola, ¿qué tal?"), inventory: inventory())?.extras.examples.count == 4)
        #expect(AssistantEngine.smallTalkReply(to: AssistantEngine.normalized("¡Muchas gracias!"), inventory: inventory()) != nil)
        #expect(AssistantEngine.smallTalkReply(to: AssistantEngine.normalized("hola de nuevo"), inventory: inventory()) != nil)
        // A greeting followed by a request is a request.
        #expect(AssistantEngine.smallTalkReply(to: AssistantEngine.normalized("Hola, ¿cómo comprimo un audio?"), inventory: inventory()) == nil)
    }

    @Test func recipesTakeNamesAndNumbersFromTheRequest() {
        #expect(AssistantEngine.requestedText(in: "crea una carpeta llamada Fotos 2026") == "Fotos 2026")
        #expect(AssistantEngine.requestedText(in: "busca la palabra TODO en el proyecto") == "TODO")
        #expect(AssistantEngine.requestedText(in: "busca “hola mundo”") == "hola mundo")
        let mkdir = RecipeBook.all.first { $0.id == "mkdir" }!
        #expect(AssistantEngine.useRecipe(mkdir, request: "crea una carpeta llamada Fotos", inventory: inventory()).proposals.first?.command == "mkdir Fotos")
        let port = RecipeBook.all.first { $0.id == "port" }!
        #expect(AssistantEngine.useRecipe(port, request: "¿qué usa el puerto 5173?", inventory: inventory()).proposals.first?.command.contains("5173") == true)
        #expect(AssistantEngine.bestRecipe(for: "¿cuál es mi ip?")?.id == "ip")
    }

    @Test func deletingMovesToTheTrash() {
        let src = ToolInventory.FileInfo(name: "src", path: "src", kind: .folder, size: 0)
        let reply = AssistantEngine.trashReply(for: "borra todo lo que hay en src", inventory: inventory(files: [src]))
        #expect(reply?.proposals.first?.command == "trash src/*")
        #expect(AssistantEngine.trashReply(for: "borra el archivo fantasma.txt", inventory: inventory(files: [src])) == nil)
    }

    @Test func writtenCommandsAreChecked() {
        let context = inventory(executables: ["wc", "git", "du", "sort", "head", "curl"])
        #expect(AssistantEngine.checkCommand("wc -l notas.md", request: "líneas de notas.md", inventory: context)?.isGenerated == true)
        #expect(AssistantEngine.checkCommand("du -sh * | sort -rh | head -5", request: "lo más pesado", inventory: context) != nil)
        #expect(AssistantEngine.checkCommand("sudo du -sh /", request: "espacio", inventory: context) == nil)
        #expect(AssistantEngine.checkCommand("rm -rf build", request: "limpia", inventory: context) == nil)
        #expect(AssistantEngine.checkCommand("inventado --flag", request: "algo", inventory: context) == nil)
        #expect(AssistantEngine.checkCommand("curl https://youtu.be/x", request: "descarga un video", inventory: context) == nil)
        #expect(AssistantEngine.checkCommand("echo hola > README.md", request: "qué es npm", inventory: context) == nil)
        #expect(AssistantEngine.checkCommand("git log --oneline | head -", request: "historial", inventory: context) != nil)
        #expect(AssistantEngine.checkCommand("echo 'sin cerrar", request: "algo", inventory: context) == nil)
        // A known tool that isn't installed comes with an Install button.
        #expect(AssistantEngine.checkCommand("gs -o chico.pdf grande.pdf", request: "comprime el pdf", inventory: context)?.missingPackage == "ghostscript")
    }

    @Test func hiddenOrDestructiveCommandsAreRejected() {
        let context = inventory(executables: ["bash", "echo", "ls", "git", "find", "sed", "sort", "python3", "xargs", "wc"])
        let accepted = [
            "bash -c 'rm -rf ~/x'", "echo $(rm -rf src)", "echo `whoami`", "ls && git reset --hard",
            "find . -name '*.log' -delete", "find . -exec rm {} +", "sed -i '' 's/a/b/' notas.md",
            "python3 -c 'import os'", "ls | xargs wc -l", "git push", "sort notas.md > notas.md",
        ].filter { AssistantEngine.checkCommand($0, request: "ordena y guarda el archivo notas.md", inventory: context) != nil }
        #expect(accepted.isEmpty)
        #expect(AssistantEngine.checkCommand("sort notas.md > ordenado-nuevo.md", request: "guarda las líneas ordenadas en un archivo", inventory: context) != nil)
    }

    @Test func dangerIsCheckedInEveryPart() {
        #expect(DangerDetector.risk(of: "ls && rm -rf build") != nil)
        #expect(DangerDetector.risk(of: "echo hola; git reset --hard") != nil)
        #expect(DangerDetector.risk(of: "bash -c 'rm -rf x'") != nil)
        #expect(DangerDetector.risk(of: "echo $(rm -rf x)") != nil)
        #expect(DangerDetector.risk(of: "find . -name '*.tmp' -delete") != nil)
        #expect(DangerDetector.risk(of: "ls -la | grep txt") == nil)
    }

    @Test func onlyRealDeletionsGoToTheTrash() {
        let files = [
            ToolInventory.FileInfo(name: "borrador.md", path: "borrador.md", kind: .other, size: 1),
            ToolInventory.FileInfo(name: "notas.txt", path: "notas.txt", kind: .other, size: 1),
            ToolInventory.FileInfo(name: "TODO.md", path: "TODO.md", kind: .other, size: 1),
            ToolInventory.FileInfo(name: "dist", path: "dist", kind: .folder, size: 0),
        ]
        let context = inventory(files: files)
        #expect(AssistantEngine.trashReply(for: "abre borrador.md", inventory: context) == nil)
        #expect(AssistantEngine.trashReply(for: "elimina los espacios de notas.txt", inventory: context) == nil)
        #expect(AssistantEngine.trashReply(for: "borra notas.txt", inventory: context)?.proposals.first?.command == "trash notas.txt")
        #expect(AssistantEngine.trashReply(for: "borra todo lo que hay en dist", inventory: context)?.proposals.first?.command == "trash dist/*")
    }

    @Test func toolListsRefreshAfterNvmCommands() {
        #expect(TerminalController.changesInstalledTools("nvm exec 24.14.0 npm uninstall -g @google/gemini-cli"))
        #expect(TerminalController.changesInstalledTools("cd x; npm i -g pnpm"))
    }

    @Test func documentsBecomePDFs() {
        let pages = ToolInventory.FileInfo(name: "Cuestionario BCI.pages", path: "/Users/demo/Cuestionario BCI.pages", kind: .document, size: 1)
        let context = inventory(attachments: [pages])
        let request = "Quiero convertir este documento en pdf comprimido y que pese poco"
        let steps = AssistantEngine.validate([AssistantStep(action: .compressPDF)], request: request, inventory: context)
        #expect(steps.map(\.action) == [.convertToPDF])
        #expect(steps.first?.compress == true)
        let reply = AssistantEngine.build(steps: steps, request: request, inventory: context)
        let command = reply.proposals.first?.command ?? ""
        #expect(command.hasPrefix("osascript -e 'tell application \"Pages\"'"))
        #expect(command.contains("POSIX file \"/Users/demo/Cuestionario BCI.pdf\""))
        #expect(command.hasSuffix("&& comprimir-pdf '/Users/demo/Cuestionario BCI.pdf' '/Users/demo/Cuestionario BCI-comprimido.pdf'"))
        #expect(DangerDetector.risk(of: command) == nil)

        let pdf = ToolInventory.FileInfo(name: "Contrato.pdf", path: "Contrato.pdf", kind: .pdf, size: 1)
        let shrink = AssistantEngine.validate([AssistantStep(action: .unknown)], request: "comprime Contrato.pdf", inventory: inventory(files: [pdf]))
        #expect(AssistantEngine.build(steps: shrink, request: "", inventory: inventory(files: [pdf])).proposals.first?.command
                == "comprimir-pdf Contrato.pdf Contrato-comprimido.pdf")
    }

    @Test func attachedPDFNeedsNoKeyword() {
        let pdf = ToolInventory.FileInfo(name: "Escaneo.pdf", path: "/tmp/Escaneo.pdf", kind: .pdf, size: 1)
        let context = inventory(attachments: [pdf])
        #expect(AssistantEngine.guess("que pese menos", inventory: context) == .compressPDF)
        let steps = AssistantEngine.validate([AssistantStep(action: .compressPDF)], request: "que pese menos", inventory: context)
        #expect(AssistantEngine.build(steps: steps, request: "", inventory: context).proposals.first?.command
                == "comprimir-pdf /tmp/Escaneo.pdf /tmp/Escaneo-comprimido.pdf")
        #expect(AssistantEngine.guess("corre el proyecto", inventory: inventory()) == .runScript)
        #expect(AssistantEngine.guess("sube mis cambios a github", inventory: inventory()) == .gitPublish)
    }

    @Test func installedAppsAndCommandsOpen() {
        var context = inventory(executables: ["agy", "gemini", "ffmpeg", "sudo", "test", "git"], files: [
            ToolInventory.FileInfo(name: "notas.md", path: "notas.md", kind: .other, size: 1),
        ])
        context.apps = [
            InstalledApp(name: "Antigravity IDE", displayName: "Antigravity IDE", path: "/Applications/Antigravity IDE.app"),
            InstalledApp(name: "Antigravity", displayName: "Antigravity", path: "/Applications/AI Development/Antigravity.app"),
            InstalledApp(name: "Gemini", displayName: "Gemini", path: "/Applications/AI Assistants/Gemini.app"),
            InstalledApp(name: "Calculator", displayName: "Calculadora", path: "/System/Applications/Calculator.app"),
        ]
        func command(_ request: String) -> String? { AssistantEngine.installedReply(for: request, inventory: context)?.proposals.first?.command }
        #expect(command("Quiero abrir antigravity CLI") == "agy")
        #expect(command("abre antigravity") == "open -a Antigravity")
        #expect(command("abre la calculadora") == "open -a Calculator")
        #expect(command("abre gemini") == "open -a Gemini")
        #expect(command("abre el cli de gemini") == "gemini")
        #expect(command("abre notas.md") == "open notas.md")
        #expect(command("ejecuta sudo rm -rf /") == nil)
        #expect(command("ejecuta los tests") == nil)
        #expect(command("abre esta carpeta en finder") == nil)
        let have = AssistantEngine.installedReply(for: "¿tengo ffmpeg instalado?", inventory: context)
        #expect(have?.explanation.hasPrefix("Sí, tienes el comando ffmpeg") == true)
        let missing = AssistantEngine.installedReply(for: "¿tengo pandoc?", inventory: context)
        #expect(missing?.explanation.contains("No encontré") == true)
        #expect(missing?.extras.suggestions.first?.package == "pandoc")
    }

    @Test func naturalWordingIsCleanedUp() {
        let reply = AssistantReply(explanation: "Voy a ver qué ocupa más espacio aquí.",
                                   proposals: [AssistantProposal(command: "du -sh * | sort -rh | head -20", tool: "du")])
        func clean(_ text: String, _ request: String = "¿qué ocupa espacio?") -> String? {
            AssistantEngine.polished(text, request: request, reply: reply)
        }
        #expect(clean("Hola. Con esto ves qué pesa más aquí. ¿Quieres probar otra cosa?") == "Con esto ves qué pesa más aquí.")
        #expect(clean("¡Hola! Te muestro qué pesa más.", "hola")?.hasPrefix("¡Hola!") == true)
        #expect(clean("Prueba con du -sh * para verlo.") == nil)
        #expect(clean("Aquí tienes los archivos más grandes.") == nil)
        #expect(clean("Ok") == nil)
    }

    @Test func sessionsGetASymbolForWhereTheyWork() throws {
        #expect(SessionSymbol.symbol(for: NSHomeDirectory()) == "house.fill")
        let folder = FileManager.default.temporaryDirectory.appending(path: "nt-sym-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "{}".write(to: folder.appending(path: "package.json"), atomically: true, encoding: .utf8)
        #expect(SessionSymbol.symbol(for: folder.path(percentEncoded: false)) == "curlybraces")
    }

    @Test func slowWorkHasADeadline() async {
        let start = ContinuousClock.now
        let result: Int? = await AssistantEngine.firstResult(within: .milliseconds(200)) {
            try? await Task.sleep(for: .seconds(30))
            return 1
        }
        #expect(result == nil)
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(ToolInventory.run(["sleep", "5"], timeout: 0.3) == nil)
        #expect(ToolInventory.run(["echo", "hola"])?.trimmingCharacters(in: .newlines) == "hola")
    }

    @Test func catalogMatchesWordForms() {
        #expect(ToolCatalog.match("comprime un pdf")?.id == "ghostscript")
        #expect(ToolCatalog.match("descarga un archivo de internet")?.id == "wget")
    }

    @Test func onlyOneStepUnlessAskedForSeveral() {
        let steps = [AssistantStep(action: .installDependencies), AssistantStep(action: .runScript, script: "test")]
        #expect(AssistantEngine.validate(steps, request: "instala las dependencias", inventory: inventory()).count == 1)
        #expect(AssistantEngine.validate(steps, request: "instala las dependencias y corre los tests", inventory: inventory()).count == 2)
    }
}

/// Real requests through Apple's on-device model. Skipped where Apple
/// Intelligence isn't available.
@Suite(.serialized, .enabled(if: AssistantEngine.isAvailable))
struct AssistantModelTests {
    private func commands(_ request: String, _ context: ToolInventory) async -> [String] {
        await AssistantEngine.reply(to: request, inventory: context).proposals.map(\.command)
    }

    @Test func runsTheRightScript() async {
        #expect(await commands("corre el servidor de storybook", inventory()) == ["npm run storybook"])
    }

    @Test func compressesTheAttachedAudio() async {
        let result = await commands("comprime este audio para mandarlo por whatsapp", inventory(attachments: [audio]))
        #expect(result.first?.hasPrefix("afconvert -f m4af -d aac") == true)
    }

    @Test func publishesToGitHub() async {
        let result = await commands("sube estos cambios a github", inventory())
        #expect(result.first?.hasPrefix("git add -A && git commit -m") == true)
        #expect(result.first?.hasSuffix("&& git push") == true)
    }

    @Test func resizesTheLogo() async {
        #expect(await commands("achica el logo a 800 px de ancho", inventory(files: [logo]))
                == ["sips --resampleWidth 800 logo.png --out logo-800px.png"])
    }

    @Test func installsWithHomebrew() async {
        let reply = await AssistantEngine.reply(to: "instala yt-dlp", inventory: inventory())
        // Either a ready command with an Install button, or the tool and how to use it.
        let mentions = reply.proposals.contains { $0.command.contains("yt-dlp") || $0.install?.contains("yt-dlp") == true }
            || reply.extras.template?.contains("yt-dlp") == true
            || reply.extras.suggestions.contains { $0.package == "yt-dlp" }
        #expect(mentions, "\(reply)")
    }

    @Test func asksWhichAudioWhenNoneIsAttached() async {
        let reply = await AssistantEngine.reply(to: "Hola, quisiera comprimir un audio, ¿cómo puedo hacer?", inventory: inventory())
        #expect(reply.extras.fileRequest?.kind == .audio, "\(reply)")
        #expect(reply.error == nil)
    }

    @Test func recommendsYtDlp() async {
        let reply = await AssistantEngine.reply(to: "¿cómo descargo un video de youtube?", inventory: inventory())
        // Either a ready command with an Install button, or the tool and how to use it.
        let mentions = reply.proposals.contains { $0.command.contains("yt-dlp") || $0.install?.contains("yt-dlp") == true }
            || reply.extras.template?.contains("yt-dlp") == true
            || reply.extras.suggestions.contains { $0.package == "yt-dlp" }
        #expect(mentions, "\(reply)")
    }

    @Test func saysWhenItCannotHelp() async {
        let reply = await AssistantEngine.reply(to: "hazme un sándwich de palta", inventory: inventory())
        #expect(reply.proposals.isEmpty)
        #expect(reply.error != nil)
    }
}
