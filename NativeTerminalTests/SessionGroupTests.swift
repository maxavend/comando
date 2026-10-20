import Foundation
import Testing
@testable import NativeTerminal

/// The folder each session is listed under when the sidebar groups by folder.
@MainActor
struct SessionGroupTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "nt-group-\(UUID().uuidString.prefix(6))")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appending(path: "tienda/.git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "tienda/src/carrito"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "fotos"), withIntermediateDirectories: true)
    }

    private func path(_ relative: String) -> String {
        root.appending(path: relative).path(percentEncoded: false).trimmingSuffix("/")
    }

    @Test func sessionsInsideARepositoryShareItsGroup() {
        let deep = TerminalSession(directory: path("tienda/src/carrito"))
        #expect(SessionGroup.folder(for: deep) == path("tienda"))
    }

    @Test func otherSessionsUseTheFolderTheyOpenedIn() {
        let photos = TerminalSession(directory: path("fotos"))
        #expect(SessionGroup.folder(for: photos) == path("fotos"))
    }

    @Test func theGroupStaysWhenTheShellMoves() {
        let session = TerminalSession(directory: path("fotos"))
        session.directory = path("tienda")
        #expect(SessionGroup.folder(for: session) == path("fotos"))
    }

    @Test func olderSessionsUseTheOldestFolderTheyVisited() {
        let session = TerminalSession(directory: path("tienda/src"))
        session.startDirectory = nil
        session.recentDirectories = [path("tienda/src"), path("fotos")]
        #expect(SessionGroup.folder(for: session) == path("fotos"))
    }
}
