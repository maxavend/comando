import Foundation

/// The folder a session belongs to in the sidebar, grouped by folder: its Git
/// repository if it was opened inside one, otherwise the folder it was opened
/// in. It doesn't change when the shell moves to another folder.
@MainActor
enum SessionGroup {
    static func folder(for session: TerminalSession) -> String {
        // Sessions from before 1.5 don't know where they started: the oldest
        // folder they visited is the closest guess.
        let start = session.startDirectory ?? session.recentDirectories.last ?? session.directory
        if let cached = cache[start] { return cached }
        let folder = repositoryRoot(containing: start) ?? start
        cache[start] = folder
        return folder
    }

    private static var cache: [String: String] = [:]

    /// The nearest folder up from `path` with a `.git`, without leaving the
    /// home folder.
    static func repositoryRoot(containing path: String) -> String? {
        let home = NSHomeDirectory()
        var current = path
        while current != "/" && !current.isEmpty {
            if FileManager.default.fileExists(atPath: current + "/.git") { return current }
            if current == home { return nil }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}

/// How the sidebar lists the sessions (Visualización › Agrupar sesiones).
enum SessionGrouping: String, CaseIterable {
    case date
    case folder

    static let key = "sessionGrouping"
}
