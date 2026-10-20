import Foundation

/// The folders the user added to the sidebar, and which of them each session
/// belongs to: the deepest added folder that holds the folder the session was
/// opened in. A session doesn't change folder when its shell moves.
@MainActor
enum SidebarFolders {
    /// UserDefaults key: the added folders, one path per line, in order.
    static let key = "sidebarFolders"

    static func list(_ stored: String) -> [String] {
        stored.split(separator: "\n").map(String.init)
    }

    static func adding(_ folder: String, to stored: String) -> String {
        let folder = folder.count > 1 ? folder.trimmingSuffix("/") : folder
        var folders = list(stored)
        guard !folders.contains(folder) else { return stored }
        folders.append(folder)
        return folders.joined(separator: "\n")
    }

    static func removing(_ folder: String, from stored: String) -> String {
        list(stored).filter { $0 != folder }.joined(separator: "\n")
    }

    /// Where the session was opened. Sessions from before 1.5 don't know: the
    /// oldest folder they visited is the closest guess.
    static func startFolder(of session: TerminalSession) -> String {
        session.startDirectory ?? session.recentDirectories.last ?? session.directory
    }

    /// The added folder the session belongs to, if any.
    static func folder(for session: TerminalSession, among folders: [String]) -> String? {
        let start = startFolder(of: session)
        return folders
            .filter { start == $0 || start.hasPrefix($0 == "/" ? "/" : $0 + "/") }
            .max { $0.count < $1.count }
    }
}
