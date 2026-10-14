import Foundation

/// A common task, described in plain words, and the command that does it.
nonisolated struct Recipe: Identifiable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case files = "Archivos y carpetas"
        case system = "Tu Mac"
        case network = "Red"
        case development = "Desarrollo"
    }

    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let category: Category
    /// Extra words people might search with.
    let keywords: [String]
    let parameters: [RecipeParameter]
    /// Builds the command from the parameter values (already trimmed).
    let build: @Sendable ([String: String]) -> String

    init(
        _ id: String,
        title: String,
        detail: String,
        systemImage: String,
        category: Category,
        keywords: [String] = [],
        parameters: [RecipeParameter] = [],
        build: @escaping @Sendable ([String: String]) -> String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.category = category
        self.keywords = keywords
        self.parameters = parameters
        self.build = build
    }

    /// The command with the current values, or with placeholders for empty ones.
    func command(with values: [String: String]) -> String {
        var filled: [String: String] = [:]
        for parameter in parameters {
            let value = values[parameter.id]?.trimmingCharacters(in: .whitespaces) ?? ""
            filled[parameter.id] = value.isEmpty ? (parameter.defaultValue ?? parameter.placeholder) : value
        }
        return build(filled)
    }

    func isComplete(_ values: [String: String]) -> Bool {
        parameters.allSatisfy { parameter in
            parameter.defaultValue != nil
                || !(values[parameter.id]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return ([title, detail] + keywords).contains { $0.localizedStandardContains(query) }
            || command(with: [:]).localizedStandardContains(query)
    }
}

nonisolated struct RecipeParameter: Identifiable, Sendable {
    enum Kind: Sendable {
        case text
        case number
        case folder
        case file
    }

    let id: String
    let label: String
    let kind: Kind
    let placeholder: String
    var defaultValue: String?
}
