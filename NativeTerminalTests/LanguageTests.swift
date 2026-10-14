import Foundation
import Testing
@testable import NativeTerminal

struct FolderNameTests {
    @Test func homeIsInicio() {
        #expect(FolderName.display(NSHomeDirectory()) == "Inicio")
        #expect(FolderName.breadcrumb(NSHomeDirectory()) == "Inicio")
        #expect(FolderName.systemImage(NSHomeDirectory()) == "house")
    }

    @Test func breadcrumbKeepsLastFolders() {
        let path = NSHomeDirectory() + "/a/b/c"
        #expect(FolderName.breadcrumb(path) == "… › b › c")
        #expect(FolderName.breadcrumb(NSHomeDirectory() + "/a") == "Inicio › a")
    }
}

struct CommandGlossaryTests {
    @Test func describesCommonCommands() {
        #expect(CommandGlossary.describe("ls -la") == "Listar archivos")
        #expect(CommandGlossary.describe("git status") == "Ver los cambios del repositorio")
        #expect(CommandGlossary.describe("git --no-pager log") == "Ver el historial de cambios")
        #expect(CommandGlossary.describe("sudo rm -rf x") == "Como administrador: Eliminar archivos")
        #expect(CommandGlossary.describe("FOO=1 /bin/ls") == "Listar archivos")
        #expect(CommandGlossary.describe("unknowncmd") == nil)
    }
}

struct ErrorExplainerTests {
    @Test func suggestsCloseCommand() {
        let hint = ErrorExplainer.hint(
            command: "gti status",
            output: "zsh: command not found: gti",
            exitCode: 127,
            knownCommands: ["git", "grep", "gzip"]
        )
        #expect(hint?.suggestion == "git status")
    }

    @Test func permissionDeniedSuggestsSudo() {
        let hint = ErrorExplainer.hint(command: "cat /etc/x", output: "cat: /etc/x: Permission denied", exitCode: 1, knownCommands: [])
        #expect(hint?.suggestion == "sudo cat /etc/x")
    }

    @Test func noHintForSuccessOrInterrupt() {
        #expect(ErrorExplainer.hint(command: "ls", output: "", exitCode: 0, knownCommands: []) == nil)
        #expect(ErrorExplainer.hint(command: "sleep 9", output: "", exitCode: 130, knownCommands: []) == nil)
    }

    @Test func editDistanceCountsSwaps() {
        #expect(ErrorExplainer.editDistance("gti", "git") == 1)
        #expect(ErrorExplainer.editDistance("kitten", "sitting") == 3)
    }
}
