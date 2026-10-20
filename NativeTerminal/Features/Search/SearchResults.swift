import SwiftUI

/// One thing the search found, and what opening it does.
enum SearchItem: Identifiable {
    /// A session whose name or folder matches.
    case session(TerminalSession)
    /// A command (or a request to the assistant) that matches.
    case command(CommandEntry)
    /// A command whose output has a matching line.
    case output(CommandEntry, line: String)
    /// A folder a session has been in.
    case folder(String)
    /// A built-in recipe for what was typed.
    case recipe(Recipe)
    /// Always last: ask the assistant in plain words.
    case ask(String)

    var id: String {
        switch self {
        case .session(let session): "session-\(session.id)"
        case .command(let entry): "command-\(entry.id)"
        case .output(let entry, _): "output-\(entry.id)"
        case .folder(let path): "folder-\(path)"
        case .recipe(let recipe): "recipe-\(recipe.id)"
        case .ask: "ask"
        }
    }
}

/// The results, grouped like the search in Messages: what matched by name
/// first, then what you did, then what you can do.
struct SearchResults {
    struct Section: Identifiable {
        let id: String
        let title: String
        let items: [SearchItem]
    }

    let sections: [Section]

    var isEmpty: Bool { sections.isEmpty }

    /// Rows shown before “Ver todo” in each section.
    static let preview = 4

    /// - Parameters:
    ///   - entries: commands whose command or output matches, newest first.
    ///   - current: the selected session, whose commands come first.
    @MainActor
    init(query: String, sessions: [TerminalSession], entries: [CommandEntry], current: UUID?,
         recipes: [Recipe] = []) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            sections = []
            return
        }
        var sections: [Section] = []

        let matchingSessions = sessions.filter {
            $0.displayName.localizedStandardContains(query)
                || FolderName.breadcrumb($0.directory).localizedStandardContains(query)
        }
        if !matchingSessions.isEmpty {
            sections.append(Section(id: "sessions", title: String(localized: "Sesiones"),
                                    items: matchingSessions.map(SearchItem.session)))
        }

        // The open session's commands first, then the rest, newest first.
        let ordered = entries.filter { $0.session?.id == current } + entries.filter { $0.session?.id != current }
        let commands = ordered.filter { $0.command.localizedStandardContains(query) }
        if !commands.isEmpty {
            sections.append(Section(id: "commands", title: String(localized: "Comandos"),
                                    items: commands.map(SearchItem.command)))
        }
        let outputs: [SearchItem] = ordered.compactMap { entry in
            guard !entry.command.localizedStandardContains(query),
                  let line = Self.matchingLine(in: entry.plainOutput, query: query) else { return nil }
            return .output(entry, line: line)
        }
        if !outputs.isEmpty {
            sections.append(Section(id: "output", title: String(localized: "En los resultados"), items: outputs))
        }

        var seen = Set<String>()
        let folders = sessions.flatMap { [$0.directory] + $0.recentDirectories }
            .filter { seen.insert($0).inserted && FolderName.display($0).localizedStandardContains(query) }
        if !folders.isEmpty {
            sections.append(Section(id: "folders", title: String(localized: "Carpetas"),
                                    items: folders.map(SearchItem.folder)))
        }

        let mine = recipes.filter { $0.category == .mine }
        if !mine.isEmpty {
            sections.append(Section(id: "mine", title: String(localized: "Mis recetas"),
                                    items: mine.map(SearchItem.recipe)))
        }
        let builtIn = recipes.filter { $0.category != .mine }
        if !builtIn.isEmpty {
            sections.append(Section(id: "recipes", title: String(localized: "Qué puedes hacer"),
                                    items: builtIn.map(SearchItem.recipe)))
        }

        sections.append(Section(id: "ask", title: "", items: [.ask(query)]))
        self.sections = sections
    }

    /// Recipes whose title, keywords or command match first; those that only
    /// mention the text in their description (“.gitignore” for “git”) last.
    nonisolated static func rankedRecipes(for query: String) -> [Recipe] {
        let found = RecipeBook.search(query)
        let direct = found.filter { recipe in
            ([recipe.title] + recipe.keywords).contains { $0.localizedStandardContains(query) }
                || recipe.command(with: [:]).localizedStandardContains(query)
        }
        return direct + found.filter { recipe in !direct.contains { $0.id == recipe.id } }
    }

    /// The first output line with the text, trimmed.
    static func matchingLine(in output: String, query: String) -> String? {
        output.split(separator: "\n", omittingEmptySubsequences: true)
            .first { $0.localizedStandardContains(query) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

extension AttributedString {
    /// `text` with every occurrence of `query` in bold, ignoring case and
    /// accents, the way search results mark what matched.
    init(_ text: String, highlighting query: String) {
        self.init(text)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let lower = AttributedString.Index(match.lowerBound, within: self),
               let upper = AttributedString.Index(match.upperBound, within: self) {
                self[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                self[lower..<upper].foregroundColor = .primary
            }
            searchRange = match.upperBound..<text.endIndex
        }
    }
}
