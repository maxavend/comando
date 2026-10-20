import Foundation
import SwiftData

/// A command the user saved as their own recipe, with a name they understand
/// and, optionally, parts that are asked for each time it's used.
@Model
final class SavedRecipe {
    var id: UUID = UUID()
    var title: String = ""
    /// The command as written, split into words (quotes kept), so a word can
    /// become a value that's asked for.
    var words: [String] = []
    var parameters: [SavedRecipeParameter] = []
    var systemImage: String = "terminal"
    var colorIndex: Int = 6
    /// Empty for no group.
    var group: String = ""
    /// The folder it was saved from.
    var directory: String = ""
    /// Always runs in `directory`, instead of the folder you're in.
    var staysInFolder: Bool = false
    /// Position in “Mis recetas”.
    var order: Int = 0
    var createdAt: Date = Date.now

    init(title: String, command: String, directory: String) {
        self.title = title
        self.words = Self.rawWords(command)
        self.directory = directory
    }

    var command: String { words.joined(separator: " ") }

    /// The command with each asked-for word replaced by its value (quoted for
    /// zsh); an empty or unchanged value keeps the word as saved.
    func command(with values: [String: String]) -> String {
        SavedRecipeCommand(words: words, parameters: parameters).command(with: values)
    }

    /// As a recipe for ⌘K and the search. `current` is the folder the
    /// session is in: a recipe tied to another folder goes there first.
    func recipe(in current: String) -> Recipe {
        let parameters = parameters.map {
            RecipeParameter(id: $0.key, label: $0.label, kind: .text,
                            placeholder: $0.defaultValue(in: words), defaultValue: $0.defaultValue(in: words))
        }
        let directory = staysInFolder ? directory : nil
        let snapshot = SavedRecipeCommand(words: words, parameters: self.parameters)
        return Recipe(
            "saved-\(id.uuidString)",
            title: title.isEmpty ? command : title,
            detail: detail,
            systemImage: systemImage,
            category: .mine,
            keywords: [group],
            parameters: parameters,
            tint: colorIndex
        ) { values in
            let line = snapshot.command(with: values)
            guard let directory, directory != current else { return line }
            return "cd \(ShellEscape.quote(directory)) && \(line)"
        }
    }

    /// What the row says under the name (the command is already beside it).
    private var detail: String {
        if !parameters.isEmpty {
            return String(localized: "Te pregunta: \(parameters.map(\.label).formatted(.list(type: .and)))")
        }
        if staysInFolder { return String(localized: "Siempre en \(FolderName.display(directory))") }
        return String(localized: "Tu receta")
    }

    /// Splits a command line at the spaces zsh would split it at, keeping each
    /// word as written (quotes and escapes included).
    static func rawWords(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in line {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if character == "\\" && quote != "'" {
                escaping = true
                current.append(character)
            } else if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if character == "'" || character == "\"" {
                quote = character
                current.append(character)
            } else if character.isWhitespace {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

/// A word of a saved recipe that's asked for when it's used.
nonisolated struct SavedRecipeParameter: Codable, Hashable, Sendable {
    var wordIndex: Int
    /// What the form asks, like “Puerto”.
    var label: String

    var key: String { "w\(wordIndex)" }

    /// The word as it was saved, without its quotes.
    func defaultValue(in words: [String]) -> String {
        guard words.indices.contains(wordIndex) else { return "" }
        return ShellEscape.words(words[wordIndex]).first ?? words[wordIndex]
    }
}

/// Builds a saved recipe's command from its words, without the SwiftData
/// object (a `Recipe` keeps a copy; the editor previews with one).
nonisolated struct SavedRecipeCommand: Sendable {
    let words: [String]
    let parameters: [SavedRecipeParameter]

    func command(with values: [String: String]) -> String {
        var filled = words
        for parameter in parameters where filled.indices.contains(parameter.wordIndex) {
            let value = values[parameter.key]?.trimmingCharacters(in: .whitespaces) ?? ""
            if !value.isEmpty, value != parameter.defaultValue(in: words) {
                filled[parameter.wordIndex] = ShellEscape.quote(value)
            }
        }
        return filled.joined(separator: " ")
    }
}
