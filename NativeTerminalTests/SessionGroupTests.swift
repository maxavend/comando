import Foundation
import Testing
@testable import NativeTerminal

/// The folders added to the sidebar and the sessions listed under each.
@MainActor
struct SessionGroupTests {
    private let folders = ["/tmp/tienda", "/tmp/tienda/api", "/tmp/fotos"]

    @Test func aSessionGoesUnderTheDeepestFolderThatHoldsIt() {
        #expect(SidebarFolders.folder(for: TerminalSession(directory: "/tmp/tienda/src"), among: folders) == "/tmp/tienda")
        #expect(SidebarFolders.folder(for: TerminalSession(directory: "/tmp/tienda/api/v2"), among: folders) == "/tmp/tienda/api")
        #expect(SidebarFolders.folder(for: TerminalSession(directory: "/tmp/fotos"), among: folders) == "/tmp/fotos")
        #expect(SidebarFolders.folder(for: TerminalSession(directory: "/tmp/tiendas"), among: folders) == nil)
    }

    @Test func itStaysWhenTheShellMoves() {
        let session = TerminalSession(directory: "/tmp/fotos")
        session.directory = "/tmp/tienda"
        #expect(SidebarFolders.folder(for: session, among: folders) == "/tmp/fotos")
    }

    @Test func olderSessionsUseTheOldestFolderTheyVisited() {
        let session = TerminalSession(directory: "/tmp/otra")
        session.startDirectory = nil
        session.recentDirectories = ["/tmp/otra", "/tmp/fotos/2024"]
        #expect(SidebarFolders.folder(for: session, among: folders) == "/tmp/fotos")
    }

    @Test func addsEachFolderOnceAndRemovesIt() {
        var stored = SidebarFolders.adding("/tmp/tienda/", to: "")
        stored = SidebarFolders.adding("/tmp/tienda", to: stored)
        stored = SidebarFolders.adding("/tmp/fotos", to: stored)
        #expect(SidebarFolders.list(stored) == ["/tmp/tienda", "/tmp/fotos"])
        #expect(SidebarFolders.list(SidebarFolders.removing("/tmp/tienda", from: stored)) == ["/tmp/fotos"])
    }
}
