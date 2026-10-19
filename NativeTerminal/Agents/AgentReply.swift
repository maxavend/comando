import Foundation

/// An agent's answer to one message, in order: text and the tools it used.
/// Stored with the entry so the conversation survives relaunch.
nonisolated struct AgentReply: Codable, Hashable, Sendable {
    nonisolated struct Step: Codable, Hashable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable { case text, tool }
        enum State: String, Codable, Sendable { case running, done, failed }

        var id: String
        var kind: Kind
        /// The text, or what the tool did (“Ejecutó un comando”).
        var text: String
        /// What the tool tried, when it didn't work (“No pudo crear saludo.txt”).
        var failedText: String?
        var symbol: String?
        /// The command or file the tool worked on, for the card.
        var detail: String?
        var output: String?
        var state: State = .done
    }

    var steps: [Step] = []
    /// Actions the agent wasn't allowed to do this turn.
    var denied: [String] = []
    var error: String?
    var isFinished = false

    /// All the text, for search and the sidebar.
    var text: String {
        steps.filter { $0.kind == .text }.map(\.text).joined()
    }

    mutating func apply(_ event: AgentEvent, agent: AgentKind) {
        switch event {
        case .conversation:
            break
        case .text(let text):
            if let last = steps.indices.last, steps[last].kind == .text {
                steps[last].text += text
            } else {
                steps.append(Step(id: "text-\(steps.count)", kind: .text, text: text))
            }
        case .toolStarted(let id, let name, let input):
            let summary = ToolSummary(agent: agent, name: name, input: input)
            if let index = steps.firstIndex(where: { $0.kind == .tool && $0.id == id }) {
                steps[index].text = summary.text
            } else {
                trimLastText()
                steps.append(Step(id: id, kind: .tool, text: summary.text, failedText: summary.failedText,
                                  symbol: summary.symbol, detail: summary.detail, state: .running))
            }
        case .toolFinished(let id, let output, let failed):
            guard let index = steps.lastIndex(where: { $0.kind == .tool && $0.id == id }) else { return }
            steps[index].output = output.map(Self.clean)
            steps[index].state = failed ? .failed : .done
        case .turnFinished(let denied, let error):
            self.denied = Array(Set(denied)).sorted()
            if let error, !error.isEmpty { self.error = error }
            finish()
        case .failed(let message):
            error = message
            finish()
        }
    }

    mutating func finish() {
        isFinished = true
        for index in steps.indices where steps[index].state == .running {
            steps[index].state = .done
        }
        trimLastText()
    }

    /// Line breaks at the edges would leave the bubble with empty lines.
    private mutating func trimLastText() {
        guard let last = steps.indices.last, steps[last].kind == .text else { return }
        steps[last].text = steps[last].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if steps[last].text.isEmpty { steps.removeLast() }
    }

    /// Terminal output with CRLF line ends and color codes, made readable.
    static func clean(_ output: String) -> String {
        let text = output.replacingOccurrences(of: "\r\n", with: "\n")
            .replacing(/\x1B\[[0-9;?]*[A-Za-z]/, with: "")
        let limit = 20_000
        return text.count > limit ? String(text.prefix(limit)) + "\n…" : text
    }
}

/// What a tool call did, in Spanish, with a symbol and the thing it touched:
/// “Leyó notas.md”, or “No pudo leer notas.md” when it failed.
nonisolated struct ToolSummary {
    var text: String
    var failedText: String
    var symbol: String
    var detail: String?

    init(agent: AgentKind, name: String, input: [String: String]) {
        func file(_ keys: String...) -> String? {
            keys.lazy.compactMap { input[$0] }.first.map { ($0 as NSString).lastPathComponent }
        }
        func value(_ keys: String...) -> String? { keys.lazy.compactMap { input[$0] }.first }

        switch name {
        case "run_command", "Bash", "command_execution", "run_shell_command", "shell":
            self.init("Ejecutó", "ejecutar", "un comando", "terminal", value("CommandLine", "command", "cmd"))
        case "view_file", "Read", "read_file", "read_many_files":
            self.init("Leyó", "leer", file("AbsolutePath", "file_path", "path", "TargetFile") ?? "un archivo", "doc.text")
        case "list_dir", "LS", "list_directory":
            self.init("Revisó", "revisar", "la carpeta " + (file("DirectoryPath", "path") ?? ""), "folder")
        case "write_to_file", "Write", "write_file":
            self.init("Creó", "crear", file("TargetFile", "file_path", "path") ?? "un archivo", "doc.badge.plus")
        case "replace_file_content", "multi_replace_file_content", "sed_file", "Edit", "MultiEdit", "replace", "edit", "NotebookEdit", "notebook_edit":
            self.init("Editó", "editar", file("TargetFile", "file_path", "path", "notebook_path") ?? "un archivo", "pencil")
        case "file_change":
            self.init("Cambió", "cambiar", value("path") ?? "archivos", "pencil")
        case "grep_search", "Grep", "search_file_content", "grep":
            self.init("Buscó", "buscar", "“\(value("Query", "pattern") ?? "")”", "magnifyingglass")
        case "find_by_name", "Glob", "glob":
            self.init("Buscó", "buscar", "archivos " + (value("Pattern", "pattern") ?? ""), "magnifyingglass")
        case "search_web", "WebSearch", "google_web_search", "web_search":
            self.init("Buscó", "buscar", "en la web “\(value("query", "Query") ?? "")”", "globe")
        case "read_url_content", "WebFetch", "web_fetch":
            let url = value("Url", "url").flatMap { URL(string: $0)?.host() } ?? ""
            self.init("Leyó", "leer", "una página " + url, "safari")
        case "TodoWrite", "manage_task", "todo_write":
            self.init("Actualizó", "actualizar", "su lista de tareas", "checklist")
        case "Task", "invoke_subagent", "browser_subagent", "Agent":
            self.init("Le pidió ayuda", "pedirle ayuda", "a un subagente", "person.2")
        default:
            let words = name.replacing(/[_-]/, with: " ").replacing(/([a-z])([A-Z])/) { "\($0.1) \($0.2)" }.lowercased()
            self.init("Usó", "usar", words, "wrench.and.screwdriver")
        }
        _ = agent
    }

    /// `past` and `infinitive` are the same verb: “Leyó”, “leer”.
    private init(_ past: String, _ infinitive: String, _ object: String, _ symbol: String, _ detail: String? = nil) {
        let object = object.trimmingCharacters(in: .whitespaces)
        text = String(localized: "\(past) \(object)").trimmingCharacters(in: .whitespaces)
        failedText = String(localized: "No pudo \(infinitive) \(object)").trimmingCharacters(in: .whitespaces)
        self.symbol = symbol
        self.detail = detail
    }
}

/// Plain-language names for actions an agent wasn't allowed to do.
nonisolated enum DeniedAction {
    static func describe(_ action: String) -> String {
        switch action {
        case "write_file", "Write", "Edit", "MultiEdit", "NotebookEdit", "replace_file_content", "file_change":
            String(localized: "crear o editar archivos")
        case "run_command", "Bash", "command":
            String(localized: "ejecutar comandos")
        case "read_url", "WebFetch", "network", "read_url_content":
            String(localized: "conectarse a internet")
        default:
            action.replacing(/[_-]/, with: " ").lowercased()
        }
    }
}
