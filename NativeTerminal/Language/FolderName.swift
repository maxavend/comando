import Foundation

/// Folder names as people see them in Finder, instead of shell paths.
nonisolated enum FolderName {
    /// “Inicio” for the home folder, Finder's localized name for everything else.
    static func display(_ path: String) -> String {
        if path == NSHomeDirectory() { return String(localized: "Inicio") }
        return FileManager.default.displayName(atPath: path)
    }

    /// “Inicio › Documentos › GitHub”, keeping only the last few folders.
    static func breadcrumb(_ path: String, maxComponents: Int = 3) -> String {
        var names: [String] = []
        var current = path
        let home = NSHomeDirectory()
        while true {
            names.insert(display(current), at: 0)
            if current == home || current == "/" { break }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { break }
            current = parent
        }
        if names.count > maxComponents {
            names = ["…"] + names.suffix(maxComponents - 1)
        }
        return names.joined(separator: " › ")
    }

    /// SF Symbol for well-known folders.
    static func systemImage(_ path: String) -> String {
        let home = NSHomeDirectory()
        switch path {
        case home: return "house"
        case home + "/Desktop": return "menubar.dock.rectangle"
        case home + "/Documents": return "doc"
        case home + "/Downloads": return "arrow.down.circle"
        case home + "/Applications", "/Applications": return "app.dashed"
        case "/": return "internaldrive"
        default: return "folder"
        }
    }
}
