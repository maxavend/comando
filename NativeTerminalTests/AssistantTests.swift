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
        #expect(!IntentDetector.isPlainLanguage("hola", knownCommands: known))
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
        #expect(installed.proposals.map(\.command) == ["yt-dlp --help"])
        #expect(installed.explanation.contains("ya la tienes"))
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
        #expect(reply.proposals.map(\.command) == ["brew install yt-dlp"], "\(reply)")
    }

    @Test func asksWhichAudioWhenNoneIsAttached() async {
        let reply = await AssistantEngine.reply(to: "Hola, quisiera comprimir un audio, ¿cómo puedo hacer?", inventory: inventory())
        #expect(reply.extras.fileRequest?.kind == .audio, "\(reply)")
        #expect(reply.error == nil)
    }

    @Test func recommendsYtDlp() async {
        let reply = await AssistantEngine.reply(to: "¿cómo descargo un video de youtube?", inventory: inventory())
        #expect(reply.proposals.map(\.command) == ["brew install yt-dlp"], "\(reply)")
    }

    @Test func saysWhenItCannotHelp() async {
        let reply = await AssistantEngine.reply(to: "hazme un sándwich de palta", inventory: inventory())
        #expect(reply.proposals.isEmpty)
        #expect(reply.error != nil)
    }
}
