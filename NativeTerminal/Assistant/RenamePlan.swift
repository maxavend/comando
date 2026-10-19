import Foundation

/// Renaming many files at once, safely: numbered names, never overwriting a
/// file that already exists (`mv -n`), and a preview of what changes before
/// anything runs.
nonisolated struct RenamePlan: Equatable, Sendable {
    /// The extension the files have, as written on disk (`jpg`, `PNG`).
    var fileExtension: String
    /// The new name before the number: `vacaciones` → `vacaciones-1.jpg`.
    var base: String

    var command: String {
        let ext = Self.globSafe(fileExtension)
        return "n=1; for f in *.\(ext)(N); do mv -n -- \"$f\" \"\(base)-$n.\(ext)\"; ((n++)); done"
    }

    /// The plan back from a command this type built, or nil.
    init?(command: String) {
        guard let match = command.wholeMatch(of: /n=1; for f in \*\.([A-Za-z0-9]+)\(N\); do mv -n -- "\$f" "([^"$\/]+)-\$n\.([A-Za-z0-9]+)"; \(\(n\+\+\)\); done/),
              match.1 == match.3 else { return nil }
        self.init(fileExtension: String(match.1), base: String(match.2))
    }

    init(fileExtension: String, base: String) {
        self.fileExtension = fileExtension
        self.base = base
    }

    /// The files it renames, in the order zsh lists them.
    func files(in directory: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.filter { !$0.hasPrefix(".") && ($0 as NSString).pathExtension == fileExtension }.sorted()
    }

    /// “Cambia el nombre de 24 archivos…”, with the first few renames.
    func preview(in directory: String) -> String {
        let files = files(in: directory)
        guard !files.isEmpty else { return String(localized: "No hay archivos .\(fileExtension) en esta carpeta.") }
        let shown = files.prefix(4).enumerated().map { "\($0.element) → \(base)-\($0.offset + 1).\(fileExtension)" }
        var text = String(localized: "Cambia el nombre de \(files.count) archivos .\(fileExtension) de esta carpeta:") + "\n" + shown.joined(separator: "\n")
        if files.count > shown.count { text += "\n" + String(localized: "…y \(files.count - shown.count) más.") }
        text += "\n" + String(localized: "No reemplaza ningún archivo que ya exista.")
        return text
    }

    /// Only letters, digits, dashes and underscores: safe inside the command.
    static func cleanBase(_ text: String) -> String {
        let words = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-_")) }
            .filter { !$0.isEmpty }
        return words.prefix(4).joined(separator: "-")
    }

    private static func globSafe(_ ext: String) -> String {
        ext.filter { $0.isLetter || $0.isNumber }
    }
}
