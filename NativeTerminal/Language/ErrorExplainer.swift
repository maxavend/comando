import Foundation

/// A plain-language explanation of a failed command, with an optional command to try.
nonisolated struct CommandHint: Equatable, Sendable {
    var message: String
    var suggestion: String?
}

/// Explains the errors people hit most often, in plain language.
nonisolated enum ErrorExplainer {
    /// Exit status of a command stopped with ⌃C (128 + SIGINT).
    static let interruptedStatus = 130

    static func hint(
        command: String,
        output: String,
        exitCode: Int?,
        knownCommands: @autoclosure () -> [String]
    ) -> CommandHint? {
        guard let exitCode, exitCode != 0, exitCode != interruptedStatus else { return nil }
        let text = output.lowercased()
        let name = ShellSession.firstWord(of: command)

        if exitCode == 127 || text.contains("command not found") {
            if let match = closestCommand(to: name, in: knownCommands()) {
                return CommandHint(
                    message: String(localized: "No existe el comando “\(name)”. ¿Quisiste decir “\(match)”?"),
                    suggestion: replacingFirstWord(of: command, with: match)
                )
            }
            return CommandHint(message: String(localized: "No existe el comando “\(name)”. Revisa cómo está escrito o si está instalado."))
        }
        if text.contains("parse error") || text.contains("unmatched") {
            return CommandHint(message: String(localized: "El comando tiene un error de escritura, como comillas o paréntesis sin cerrar."))
        }
        if text.contains("operation not permitted") {
            return CommandHint(message: String(localized: "macOS bloqueó el acceso. Puedes darle acceso total al disco a NativeTerminal en Ajustes del Sistema › Privacidad y seguridad."))
        }
        if text.contains("permission denied") {
            let trimmed = command.trimmingCharacters(in: .whitespaces)
            return CommandHint(
                message: String(localized: "No tienes permiso para hacer esto."),
                suggestion: trimmed.hasPrefix("sudo ") ? nil : "sudo " + trimmed
            )
        }
        if text.contains("no such file or directory") {
            return CommandHint(message: String(localized: "No se encontró ese archivo o carpeta. Revisa el nombre; Tab te ayuda a completarlo."))
        }
        if text.contains("not a git repository") {
            return CommandHint(message: String(localized: "Esta carpeta no es un repositorio de Git."))
        }
        if text.contains("could not resolve host") || text.contains("unknown host") {
            return CommandHint(message: String(localized: "No se pudo llegar a esa dirección. Revisa tu conexión o el nombre."))
        }
        return nil
    }

    /// The known command closest to `name`, if it is a plausible typo.
    static func closestCommand(to name: String, in commands: [String]) -> String? {
        guard name.count >= 2 else { return nil }
        let limit = name.count <= 3 ? 1 : 2
        var best: (name: String, distance: Int)?
        for candidate in commands where abs(candidate.count - name.count) <= limit && candidate != name {
            let distance = editDistance(name, candidate)
            guard distance <= limit else { continue }
            if let current = best, distance > current.distance || (distance == current.distance && candidate >= current.name) {
                continue
            }
            best = (candidate, distance)
        }
        return best?.name
    }

    /// Optimal string alignment distance: edits plus adjacent swaps (“gti” → “git”).
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }

    private static func replacingFirstWord(of command: String, with word: String) -> String {
        let trimmed = command.drop { $0 == " " }
        let rest = trimmed.drop { $0 != " " }
        return word + rest
    }
}
