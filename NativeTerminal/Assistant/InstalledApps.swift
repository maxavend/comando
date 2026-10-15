import Foundation

/// An app on this Mac, by the name people see in Finder.
nonisolated struct InstalledApp: Sendable, Hashable {
    /// The bundle's file name without `.app` (“Calculator”).
    var name: String
    /// The name Finder shows, in the user's language (“Calculadora”).
    var displayName: String
    var path: String
}

/// Finds apps and command-line tools on this Mac by a loosely written name,
/// so “abre antigravity” or “¿tengo ffmpeg?” work without the model.
nonisolated enum InstalledApps {
    private static var roots: [String] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
         NSHomeDirectory() + "/Applications"]
    }

    /// Apps in the usual folders, including folders inside them (people
    /// group apps in “/Applications/Design” and the like).
    static func list() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        func add(_ path: String) {
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard seen.insert(name).inserted else { return }
            let shown = (FileManager.default.displayName(atPath: path) as NSString).deletingPathExtension
            apps.append(InstalledApp(name: name, displayName: shown, path: path))
        }
        for root in roots {
            for item in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where !item.hasPrefix(".") {
                let path = (root as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") {
                    add(path)
                } else if root == "/Applications" || root.hasSuffix("/Applications") {
                    for inner in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] where inner.hasSuffix(".app") {
                        add((path as NSString).appendingPathComponent(inner))
                    }
                }
            }
        }
        add("/System/Library/CoreServices/Finder.app")
        return apps
    }

    /// Command-line tools that apps install under a different name.
    static let companionCommands: [String: String] = [
        "antigravity": "agy", "visual studio code": "code", "vs code": "code", "vscode": "code", "code": "code",
        "cursor": "cursor", "sublime": "subl", "zed": "zed", "kiro": "kiro", "android studio": "studio",
        "github desktop": "github", "xcode": "xed", "lm studio": "lms", "docker": "docker", "windsurf": "windsurf",
    ]

    /// Words that describe the thing rather than name it.
    private static let filler: Set<String> = [
        "app", "apps", "aplicacion", "programa", "cli", "comando", "terminal", "consola", "herramienta", "version",
        "nueva", "nuevo", "porfa", "favor", "instalado", "instalada", "ahora", "mac", "ide",
    ]

    /// The meaningful words of a name or request.
    static func tokens(_ text: String) -> [String] {
        AssistantEngine.keywords(in: text).filter { !filler.contains($0) }.sorted()
    }

    private static func sameWord(_ a: String, _ b: String) -> Bool {
        a == b || (min(a.count, b.count) >= 4 && (a.hasPrefix(b) || b.hasPrefix(a)))
    }

    /// The app whose name contains every word of `target`, preferring the
    /// closest name (“antigravity” → “Antigravity IDE”).
    static func findApp(_ target: String, in apps: [InstalledApp]) -> InstalledApp? {
        // “Abre la terminal” is all filler words, and that's the name itself.
        var wanted = tokens(target)
        if wanted.isEmpty {
            wanted = AssistantEngine.keywords(in: target).filter { !["app", "apps", "aplicacion", "programa"].contains($0) }.sorted()
        }
        guard !wanted.isEmpty else { return nil }
        let matches = apps.compactMap { app -> (InstalledApp, Int)? in
            let names = [AssistantEngine.keywords(in: app.displayName), AssistantEngine.keywords(in: app.name)]
            guard let name = names.first(where: { name in
                wanted.allSatisfy { word in name.contains { candidate in sameWord(candidate, word) || synonyms[word]?.contains(candidate) == true } }
            }) else { return nil }
            return (app, name.count - wanted.count)
        }
        return matches.min { $0.1 < $1.1 }?.0
    }

    /// Other words people use for the same app.
    private static let synonyms: [String: Set<String>] = [
        "configuracion": ["ajustes", "settings"], "preferencias": ["ajustes", "settings"], "settings": ["ajustes"],
        "ajustes": ["settings"], "calculadora": ["calculator"], "navegador": ["safari", "chrome"],
        "correo": ["mail"], "fotos": ["photos"], "musica": ["music"], "notas": ["notes"], "mensajes": ["messages"],
    ]

    /// A command on `$PATH` that the request names, directly (“gemini”) or
    /// through its app (“antigravity” → `agy`).
    static func findCommand(_ target: String, app: InstalledApp?, executables: Set<String>) -> String? {
        let text = " " + AssistantEngine.normalized(target) + " "
        for (key, command) in companionCommands where executables.contains(command) {
            if text.contains(" \(key) ") { return command }
            if let app, AssistantEngine.normalized(app.name).contains(key) { return command }
        }
        // A command named on its own (“abre gemini cli”), never a generic or
        // risky one picked out of a longer request (“ejecuta sudo rm …”).
        let wanted = tokens(target)
        guard wanted.count == 1, let word = wanted.first, executables.contains(word), !unsuitable.contains(word) else { return nil }
        return word
    }

    private static let unsuitable: Set<String> = [
        "sudo", "su", "rm", "rmdir", "mv", "cp", "dd", "kill", "killall", "shutdown", "reboot", "halt", "test", "true",
        "false", "yes", "time", "open", "which", "cd", "ls", "make", "find", "say", "man", "top", "login", "logout", "exit",
    ]

    /// Installed apps and commands related to a request, for the model's context.
    static func related(to request: String, inventory: ToolInventory) -> [String] {
        let wanted = tokens(request).filter { $0.count >= 4 }
        guard !wanted.isEmpty else { return [] }
        var found: [String] = inventory.apps.filter { app in
            let name = AssistantEngine.keywords(in: app.displayName + " " + app.name)
            return wanted.contains { word in name.contains { sameWord($0, word) } }
        }.prefix(4).map { "\($0.displayName) (app)" }
        if let command = findCommand(request, app: nil, executables: inventory.executables) {
            found.append("\(command) (comando)")
        }
        return found
    }
}
