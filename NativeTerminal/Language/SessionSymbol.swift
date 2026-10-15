import Foundation

/// An SF Symbol for a session, from where it works: a known folder (home,
/// Desktop, Downloads…) or the kind of project inside it (Swift, Node,
/// Python, a Git repository…). The terminal symbol otherwise.
enum SessionSymbol {
    private static var cache: [String: String] = [:]

    static func symbol(for directory: String) -> String {
        if let cached = cache[directory] { return cached }
        let symbol = folderSymbol(directory) ?? projectSymbol(directory) ?? "apple.terminal.fill"
        cache[directory] = symbol
        return symbol
    }

    private static func folderSymbol(_ directory: String) -> String? {
        let home = NSHomeDirectory()
        return [
            home: "house.fill",
            home + "/Desktop": "menubar.dock.rectangle",
            home + "/Documents": "doc.fill",
            home + "/Downloads": "arrow.down.circle.fill",
            home + "/Pictures": "photo.fill",
            home + "/Movies": "film.fill",
            home + "/Music": "music.note",
            "/": "internaldrive.fill",
        ][directory]
    }

    /// The first marker found wins, from the most to the least specific.
    private static func projectSymbol(_ directory: String) -> String? {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
        func has(_ candidates: String...) -> Bool { candidates.contains(where: names.contains) }
        if has("Package.swift", "project.yml") || names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            return "swift"
        }
        if has("Cargo.toml") { return "gearshape.2.fill" }
        if has("package.json") { return "curlybraces" }
        if has("pyproject.toml", "requirements.txt", "setup.py", "Pipfile") { return "chevron.left.forwardslash.chevron.right" }
        if has("Dockerfile", "compose.yaml", "docker-compose.yml") { return "shippingbox.fill" }
        if has(".git") { return "arrow.triangle.branch" }
        return nil
    }
}
