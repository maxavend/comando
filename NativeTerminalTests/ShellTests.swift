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
