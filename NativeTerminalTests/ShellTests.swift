import Foundation
import Testing
@testable import NativeTerminal

struct ShellEscapeTests {
    @Test func quotesOnlyWhenNeeded() {
        #expect(ShellEscape.quote("file.txt") == "file.txt")
        #expect(ShellEscape.quote("My File.txt") == "'My File.txt'")
        #expect(ShellEscape.quote("it's") == #"'it'\''s'"#)
        #expect(ShellEscape.quote("") == "''")
    }

    @Test func backslashRoundTrip() {
        let name = "My (old) file's.txt"
        let escaped = ShellEscape.addBackslashes(name)
        #expect(escaped == #"My\ \(old\)\ file\'s.txt"#)
        #expect(ShellEscape.removeBackslashes(escaped) == name)
        #expect(ShellEscape.addBackslashes("~/Docs") == "~/Docs")
    }

    @Test func abbreviatesHome() {
        let home = NSHomeDirectory()
        #expect(ShellEscape.abbreviate(home) == "~")
        #expect(ShellEscape.abbreviate(home + "/Desktop") == "~/Desktop")
        #expect(ShellEscape.abbreviate("/usr/bin") == "/usr/bin")
    }
}

struct ShellSessionHelperTests {
    @Test func firstWord() {
        #expect(ShellSession.firstWord(of: "  ssh host") == "ssh")
        #expect(ShellSession.firstWord(of: "/usr/bin/python3 -q") == "python3")
    }

    @Test func parseErrorOutputAfterLineAccepted() {
        let bytes = Array("git sta\u{1B}[?2004l\r\r\nzsh: parse error near `)'\r\n".utf8)
        let output = String(decoding: ShellSession.bytesAfterLineAccepted(bytes), as: UTF8.self)
        #expect(output == "zsh: parse error near `)'\r\n")
    }
}

@MainActor
struct CompletionProviderTests {
    @Test func splitsLastWordHonoringEscapes() {
        #expect(CompletionProvider.splitLastWord("git checkout ma") == ("git checkout ", "ma"))
        #expect(CompletionProvider.splitLastWord(#"cd My\ Fo"#) == ("cd ", #"My\ Fo"#))
        #expect(CompletionProvider.splitLastWord("ls") == ("", "ls"))
    }

    @Test func completesPathsInDirectory() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appending(path: "Project Files"), withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "readme.md"))
        defer { try? FileManager.default.removeItem(at: folder) }

        let provider = CompletionProvider()
        let directory = folder.path(percentEncoded: false)
        let suggestions = provider.suggestions(for: "cd Pro", directory: directory, pathEntries: [], history: [])
        #expect(suggestions.map(\.completion) == [#"cd Project\ Files/"#])

        #expect(provider.tabCompletion(for: "cat rea", directory: directory, pathEntries: []) == "cat readme.md ")
    }

    @Test func historyComesFirst() {
        let provider = CompletionProvider()
        let suggestions = provider.suggestions(
            for: "git s",
            directory: "/",
            pathEntries: [],
            history: ["git status", "ls", "git stash"]
        )
        #expect(suggestions.first?.completion == "git stash")
        #expect(suggestions.first?.kind == .history)
    }
}

@MainActor
struct ContextualCompletionTests {
    @Test func suggestsSubcommandsOptionsAndSignals() throws {
        let git = try #require(ContextualCompletion(text: "git lo"))
        #expect(git.staticMatches.map(\.completion) == ["git log "])
        let option = try #require(ContextualCompletion(text: "git log --on"))
        #expect(option.staticMatches.map(\.completion) == ["git log --oneline "])
        let npm = try #require(ContextualCompletion(text: "npm install --save-"))
        #expect(npm.staticMatches.map(\.completion) == ["npm install --save-dev ", "npm install --save-exact "])
        let signal = try #require(ContextualCompletion(text: "kill -TE"))
        #expect(signal.staticMatches.map(\.completion) == ["kill -TERM "])
        #expect(ContextualCompletion(text: "git add -- --on") == nil)
        #expect(ContextualCompletion(text: "echo hi; git lo") == nil)
        #expect(ContextualCompletion(text: "git log\n") == nil)
    }

    @Test func usesGenericSuggestionsAsFallback() throws {
        let context = try #require(ContextualCompletion(text: "git log --on"))
        let provider = CompletionProvider()
        let suggestions = provider.suggestions(
            for: "git log --on", directory: "/", pathEntries: [],
            history: ["git log --oneline -5"], limit: 2, contextual: context.staticMatches
        )
        #expect(suggestions.map(\.kind) == [.option])
        #expect(ContextualCompletion(text: "git add Re") == nil)
    }

    @Test func readsScriptsFromNearestManifestAndQuotesNames() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let child = root.appending(path: "Project Files")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"scripts":{"dev":"echo ignored","dev preview":"echo ignored","test":"echo ignored"}}"#
            .write(to: root.appending(path: "package.json"), atomically: true, encoding: .utf8)
        let context = try #require(ContextualCompletion(text: "npm run de"))
        let suggestions = await context.lookup(in: child.path(percentEncoded: false))
        #expect(suggestions.map(\.completion) == ["npm run dev ", "npm run 'dev preview' "])

        try "invalid".write(to: child.appending(path: "package.json"), atomically: true, encoding: .utf8)
        #expect(await context.lookup(in: child.path(percentEncoded: false)).isEmpty)
    }

    @Test func readsLocalGitBranchesFromASubfolder() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let child = root.appending(path: "nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.path(percentEncoded: false)
        try git(["init", "-q"], in: directory)
        try git(["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                 "commit", "--allow-empty", "-qm", "Initial"], in: directory)
        try git(["branch", "feature/new-ui"], in: directory)

        let branch = try #require(ContextualCompletion(text: "git switch feature/n"))
        let suggestions = await branch.lookup(in: child.path(percentEncoded: false))
        #expect(suggestions.map(\.completion) == ["git switch feature/new-ui "])
        let deletion = try #require(ContextualCompletion(text: "git branch -d feat"))
        #expect(await deletion.lookup(in: directory).map(\.completion) == ["git branch -d feature/new-ui "])
    }

    @Test func processSuggestionsOnlyInsertMatchingOwnedPositivePIDs() throws {
        let context = try #require(ContextualCompletion(text: "kill -TERM 12"))
        let results = context.processMatches([
            "501 123 /opt/homebrew/bin/node", "501 120 bash", "502 121 other",
            "501 124 Comando", "501 7 unrelated", "broken"
        ], uid: 501, excluding: 124)
        #expect(results.map(\.title) == ["120 · bash", "123 · node"])
        #expect(results.map(\.completion) == ["kill -TERM 120 ", "kill -TERM 123 "])
        #expect(ContextualCompletion(text: "kill 0") == nil)
    }

    private func git(_ arguments: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", directory, "-c", "core.hooksPath=/dev/null"] + arguments
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}

struct ShellLanguageTests {
    private let installed: Set<String> = ["es_ES.UTF-8", "es_MX.UTF-8", "en_US.UTF-8", "pt_BR.UTF-8"]

    @Test func keepsAnInstalledRegion() {
        #expect(ShellIntegration.language(for: "es", region: "MX", available: installed) == "es_MX.UTF-8")
    }

    /// There is no es_CL.UTF-8 on macOS: `cal` printed “setlocale: No such file or directory”.
    @Test func fallsBackWhenTheRegionHasNoLocale() {
        #expect(ShellIntegration.language(for: "es", region: "CL", available: installed) == "es_ES.UTF-8")
        #expect(ShellIntegration.language(for: "pt", region: "PT", available: installed) == "pt_BR.UTF-8")
        #expect(ShellIntegration.language(for: "xx", region: "YY", available: installed) == "en_US.UTF-8")
        #expect(ShellIntegration.language(for: nil, region: nil, available: installed) == "en_US.UTF-8")
    }
}
