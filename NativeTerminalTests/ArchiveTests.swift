import Foundation
import SwiftData
import Testing
@testable import NativeTerminal

/// Selecting several sessions, archiving and deleting them.
@MainActor
@Suite(.serialized)
final class ArchiveTests {
    private let container: ModelContainer
    private let controller: TerminalController

    init() throws {
        container = try ModelContainer(
            for: TerminalSession.self, CommandEntry.self, SavedRecipe.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        controller = TerminalController(modelContext: container.mainContext)
    }

    isolated deinit {
        controller.terminateAll()
        for shell in controller.shells.values { shell.delegate = nil }
    }

    private func sessions() -> [TerminalSession] {
        (try? container.mainContext.fetch(FetchDescriptor<TerminalSession>())) ?? []
    }

    @Test func archivingMovesTheSelectionToAnActiveSession() {
        let a = controller.createSession(directory: "/tmp")
        let b = controller.createSession(directory: "/var")
        b.isPinned = true
        controller.selectInSidebar([a.id, b.id])

        controller.archive([a, b])

        #expect(a.isArchived && b.isArchived)
        #expect(!b.isPinned)
        let selected = controller.selectedSession
        #expect(selected != nil && selected?.isArchived == false)
        #expect(controller.selectedSessionIDs == [selected!.id])
    }

    @Test func writingInAnArchivedSessionBringsItBack() {
        let session = controller.createSession(directory: "/tmp")
        controller.archive([session])
        controller.selectedSessionID = session.id
        controller.ask("hola", attachments: [], in: session)
        #expect(!session.isArchived)
    }

    @Test func deletesSeveralAtOnce() {
        let a = controller.createSession(directory: "/tmp")
        let b = controller.createSession(directory: "/var")
        let before = sessions().count
        controller.delete([a, b])
        #expect(sessions().count == before - 2 + (before == 2 ? 1 : 0))
        #expect(!sessions().contains { $0.id == a.id || $0.id == b.id })
    }

    @Test func choosingOneSessionReplacesASelectionOfSeveral() {
        let a = controller.createSession(directory: "/tmp")
        let b = controller.createSession(directory: "/var")
        let c = controller.createSession(directory: "/usr")
        controller.selectInSidebar([a.id, b.id])
        #expect(controller.selectedSessionIDs == [a.id, b.id])
        controller.selectedSessionID = c.id
        #expect(controller.selectedSessionIDs == [c.id])
        // A search result in the selection still leaves only that one.
        controller.selectInSidebar([a.id, c.id])
        controller.selectedSessionID = c.id
        #expect(controller.selectedSessionIDs == [c.id])
    }
}
