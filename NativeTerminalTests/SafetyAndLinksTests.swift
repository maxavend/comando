import Foundation
import Testing
@testable import NativeTerminal

struct DangerDetectorTests {
    @Test func flagsRiskyCommands() {
        #expect(DangerDetector.risk(of: "rm -rf build") != nil)
        #expect(DangerDetector.risk(of: "rm *.log") != nil)
        #expect(DangerDetector.risk(of: "sudo ls") != nil)
        #expect(DangerDetector.risk(of: "git reset --hard HEAD~1") != nil)
        #expect(DangerDetector.risk(of: "git push --force") != nil)
        #expect(DangerDetector.risk(of: "curl -fsSL https://x.sh | sh") != nil)
        #expect(DangerDetector.risk(of: "chmod -R 777 .") != nil)
    }

    @Test func allowsEverydayCommands() {
        #expect(DangerDetector.risk(of: "rm notes.txt") == nil)
        #expect(DangerDetector.risk(of: "ls -la") == nil)
        #expect(DangerDetector.risk(of: "git status") == nil)
        #expect(DangerDetector.risk(of: "git push") == nil)
        #expect(DangerDetector.risk(of: "curl https://example.com") == nil)
    }
}

struct OutputLinkerTests {
    private func makeFolder() throws -> String {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appending(path: "My Folder"), withIntermediateDirectories: true)
        try Data().write(to: folder.appending(path: "readme.md"))
        try Data().write(to: folder.appending(path: "a b.txt"))
        return folder.path(percentEncoded: false)
    }

    @Test func findsNamesInColumns() throws {
        let folder = try makeFolder()
        let names = OutputLinker.names(in: "My Folder  a b.txt    readme.md", folder: folder).map(\.2)
        #expect(names == ["My Folder", "a b.txt", "readme.md"])
    }

    @Test func findsNameAtEndOfLongListing() throws {
        let folder = try makeFolder()
        let line = "-rw-r--r--  1 me  staff  0 Oct 14 12:00 a b.txt"
        #expect(OutputLinker.names(in: line, folder: folder).map(\.2) == ["a b.txt"])
    }

    @Test func linksOnlyLsCommands() throws {
        let folder = try makeFolder()
        #expect(OutputLinker.listedFolder(command: "ls -G", directory: folder) == folder)
        #expect(OutputLinker.listedFolder(command: "cat readme.md", directory: folder) == nil)
        #expect(OutputLinker.listedFolder(command: #"ls My\ Folder"#, directory: folder)?.hasSuffix("My Folder") == true)
    }

    @Test func linkifyAddsFileURLs() throws {
        let folder = try makeFolder()
        let linked = OutputLinker.linkify(AttributedString("readme.md\nnope"), folder: folder)
        let links = linked.runs.compactMap(\.link)
        #expect(links.count == 1)
        #expect(links.first?.lastPathComponent == "readme.md")
    }
}

struct URLLinkTests {
    @Test func linksWebAddresses() {
        let linked = OutputLinker.linkifyURLs(AttributedString("- Local: http://localhost:6006/ ok"))
        #expect(linked.runs.compactMap(\.link).map(\.absoluteString) == ["http://localhost:6006/"])
    }

    @Test func findsLocalServer() {
        let text = "Docs: https://storybook.js.org\n- Local: http://localhost:6006/\n- Network: http://192.168.1.5:6006/"
        #expect(OutputLinker.firstLocalURL(in: text)?.absoluteString == "http://localhost:6006/")
        #expect(OutputLinker.firstLocalURL(in: "nothing here") == nil)
    }
}

struct SingleSpaceColumnsTests {
    @Test func greedyNamesWithSingleSpaces() {
        let entries: Set<String> = ["Carpeta Uno", "notas.txt", "a"]
        let names = OutputLinker.names(in: "Carpeta Uno notas.txt a", entries: entries).map(\.2)
        #expect(names == ["Carpeta Uno", "notas.txt", "a"])
        #expect(OutputLinker.names(in: "Carpeta/ notas.txt*", entries: ["Carpeta", "notas.txt"]).map(\.2) == ["Carpeta", "notas.txt"])
    }
}
