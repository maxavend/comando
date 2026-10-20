import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import NativeTerminal

/// The sidebar search: what each section collects and in what order.
@MainActor
struct SearchTests {
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: TerminalSession.self, CommandEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func session(_ directory: String) -> TerminalSession {
        let session = TerminalSession(directory: directory)
        container.mainContext.insert(session)
        return session
    }

    private func entry(_ command: String, output: String = "", in session: TerminalSession) -> CommandEntry {
        let entry = CommandEntry(command: command, directory: session.directory, session: session)
        entry.plainOutput = output
        container.mainContext.insert(entry)
        return entry
    }

    private func ids(_ results: SearchResults) -> [String] { results.sections.map(\.id) }

    @Test func groupsWhatMatchedAndEndsWithAsking() {
        let web = session("/tmp/tienda-web")
        web.recentDirectories = ["/tmp/tienda-web/src"]
        let other = session("/tmp/otra")
        let status = entry("git status", output: "On branch main", in: web)
        let log = entry("ls", output: "tienda-web.zip", in: other)

        let results = SearchResults(query: "tienda", sessions: [web, other], entries: [status, log], current: nil,
                                    recipes: [])
        #expect(ids(results) == ["sessions", "output", "folders", "ask"])
        #expect(results.sections.first?.items.count == 1)
        if case .output(_, let line) = results.sections[1].items.first {
            #expect(line == "tienda-web.zip")
        } else {
            Issue.record("Falta la línea de la salida")
        }
    }

    @Test func commandsOfTheOpenSessionComeFirst() {
        let a = session("/tmp/a")
        let b = session("/tmp/b")
        let older = entry("git pull", in: a)
        let newer = entry("git push", in: b)
        let results = SearchResults(query: "git", sessions: [a, b], entries: [newer, older], current: a.id)
        let commands = results.sections.first { $0.id == "commands" }?.items.map(\.id)
        #expect(commands == ["command-\(older.id)", "command-\(newer.id)"])
    }

    @Test func emptyQueryFindsNothing() {
        #expect(SearchResults(query: "  ", sessions: [], entries: [], current: nil).isEmpty)
    }

    @Test func highlightIgnoresCaseAndAccents() {
        let text = AttributedString("Canción y CANCION", highlighting: "cancion")
        let bold = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(text[$0.range].characters) }
        #expect(bold == ["Canción", "CANCION"])
    }
}

struct SearchRecipeRankingTests {
    /// “Ver archivos ocultos” only mentions .gitignore: it goes after the Git recipes.
    @Test func directMatchesComeFirst() {
        let ids = SearchResults.rankedRecipes(for: "git").map(\.id)
        #expect(ids.firstIndex(of: "hidden").map { $0 > 0 } ?? true)
        #expect(ids.first != "hidden")
    }
}
