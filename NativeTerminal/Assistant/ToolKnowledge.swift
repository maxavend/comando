import Foundation

/// A command-line tool the assistant can propose, found on this Mac, in the
/// Homebrew catalog or on npm.
nonisolated struct DiscoveredTool: Sendable, Hashable {
    enum Source: String, Sendable { case installed, homebrew, npm }

    /// The package name (what gets installed).
    var package: String
    /// The command it adds (often the same as the package).
    var command: String
    /// What it does, as its catalog says (usually English).
    var summary: String
    var source: Source
    var isInstalled: Bool
    /// Weekly downloads, for npm packages.
    var weeklyDownloads: Int?

    var installCommand: String? {
        guard !isInstalled else { return nil }
        switch source {
        case .homebrew: return "brew install " + ShellEscape.quote(package)
        case .npm: return "npm install -g " + ShellEscape.quote(package)
        case .installed: return nil
        }
    }

    /// “Homebrew”, “npm · 52 mil descargas por semana”, “instalada”.
    var origin: String {
        if isInstalled { return String(localized: "instalada") }
        switch source {
        case .homebrew: return "Homebrew"
        case .npm:
            guard let weeklyDownloads else { return "npm" }
            let count = weeklyDownloads.formatted(.number.notation(.compactName).locale(Locale(identifier: "es")))
            return String(localized: "npm · \(count) descargas por semana")
        case .installed: return String(localized: "instalada")
        }
    }
}

/// A tldr page: what a command does and real examples of how to call it.
nonisolated struct ToolExamples: Sendable, Hashable {
    var description: String
    /// (what it does, the command line) pairs.
    var examples: [(String, String)]
    var isSpanish: Bool

    static func == (lhs: ToolExamples, rhs: ToolExamples) -> Bool {
        lhs.description == rhs.description && lhs.examples.map(\.1) == rhs.examples.map(\.1)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(description) }
}

/// What the assistant knows about terminal tools beyond this Mac: the
/// Homebrew catalog and tldr examples, downloaded and searched locally, and
/// npm, searched live. Only search words ever leave the Mac.
actor ToolKnowledge {
    static let shared = ToolKnowledge()

    private struct Formula: Codable { var name: String; var desc: String }

    private var formulae: [Formula]?
    private var isPreparing = false

    static var directory: URL {
        ShellIntegration.directory.deletingLastPathComponent().appending(path: "Conocimiento", directoryHint: .isDirectory)
    }

    private var catalogURL: URL { Self.directory.appending(path: "homebrew.json") }
    private var tldrURL: URL { Self.directory.appending(path: "tldr", directoryHint: .isDirectory) }

    // MARK: - Downloading

    /// Downloads or refreshes the Homebrew catalog (weekly) and tldr pages
    /// (monthly). Quiet on failure: the assistant works without them.
    func prepare() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if Self.isStale(catalogURL, days: 7) {
            await downloadCatalog()
        }
        if Self.isStale(tldrURL.appending(path: "es"), days: 30) {
            await downloadTldr()
        }
        // Ready in memory before the first search.
        _ = loadedFormulae()
        _ = loadedPageIndex()
    }

    private static func isStale(_ url: URL, days: Double) -> Bool {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date else { return true }
        return Date.now.timeIntervalSince(date) > days * 86_400
    }

    private func downloadCatalog() async {
        guard let url = URL(string: "https://formulae.brew.sh/api/formula.json"),
              let (data, _) = try? await Self.session.data(from: url),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let compact = list.compactMap { item -> Formula? in
            guard let name = item["name"] as? String else { return nil }
            return Formula(name: name, desc: item["desc"] as? String ?? "")
        }
        guard !compact.isEmpty, let encoded = try? JSONEncoder().encode(compact) else { return }
        try? encoded.write(to: catalogURL, options: .atomic)
        formulae = compact
    }

    private func downloadTldr() async {
        for language in ["es", "en"] {
            guard let url = URL(string: "https://github.com/tldr-pages/tldr/releases/latest/download/tldr-pages.\(language).zip"),
                  let (file, _) = try? await Self.session.download(from: url) else { continue }
            let destination = tldrURL.appending(path: language, directoryHint: .isDirectory)
            let staging = tldrURL.appending(path: "\(language)-nuevo", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            guard ToolInventory.run(["ditto", "-x", "-k", file.path(percentEncoded: false), staging.path(percentEncoded: false)], timeout: 60) != nil else { continue }
            // Only the pages that apply to a Mac.
            for platform in (try? FileManager.default.contentsOfDirectory(atPath: staging.path(percentEncoded: false))) ?? []
            where !["common", "osx"].contains(platform) {
                try? FileManager.default.removeItem(at: staging.appending(path: platform))
            }
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: staging, to: destination)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    // MARK: - Homebrew

    private func loadedFormulae() -> [Formula] {
        if let formulae { return formulae }
        let loaded = (try? JSONDecoder().decode([Formula].self, from: Data(contentsOf: catalogURL))) ?? []
        formulae = loaded
        return loaded
    }

    /// Formulae whose name or description share the most words with the
    /// English keywords.
    func searchHomebrew(_ keywords: [String], limit: Int = 5) -> [(name: String, summary: String, score: Int)] {
        let wanted = Set(keywords.flatMap { AssistantEngine.keywords(in: $0) }).filter { $0.count >= 3 }
        guard !wanted.isEmpty else { return [] }
        var scored: [(name: String, summary: String, score: Int)] = []
        for formula in loadedFormulae() {
            let name = formula.name.lowercased()
            let words = AssistantEngine.keywords(in: formula.desc)
            var score = 0
            for word in wanted {
                if name == word { score += 4 }
                else if words.contains(where: { ToolCatalog.sameStem($0, word) }) { score += 2 }
                else if name.contains(word) { score += 1 }
            }
            if score >= 2 { scored.append((formula.name, formula.desc, score)) }
        }
        // Ties go to shorter, more general names (“qpdf” before “qpdf-extras”).
        return Array(scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.name.count < $1.name.count }.prefix(limit))
    }

    // MARK: - npm

    /// Packages that install a command, with enough weekly downloads to be
    /// trustworthy (look-alike names are a known risk on npm).
    func searchNPM(_ keywords: [String], limit: Int = 3, minimumDownloads: Int = 10_000) async -> [DiscoveredTool] {
        let text = keywords.joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard !text.isEmpty, let url = URL(string: "https://registry.npmjs.org/-/v1/search?text=\(text)+keywords:cli&size=10"),
              let (data, _) = try? await Self.session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["objects"] as? [[String: Any]] else { return [] }
        let packages = results.compactMap { $0["package"] as? [String: Any] }.prefix(6)
        return await withTaskGroup(of: DiscoveredTool?.self) { group in
            for package in packages {
                guard let name = package["name"] as? String else { continue }
                let summary = package["description"] as? String ?? ""
                group.addTask { await Self.npmTool(name: name, summary: summary, minimumDownloads: minimumDownloads) }
            }
            var tools: [DiscoveredTool] = []
            for await tool in group { if let tool { tools.append(tool) } }
            return Array(tools.sorted { ($0.weeklyDownloads ?? 0) > ($1.weeklyDownloads ?? 0) }.prefix(limit))
        }
    }

    private static func npmTool(name: String, summary: String, minimumDownloads: Int) async -> DiscoveredTool? {
        let escaped = name.replacingOccurrences(of: "/", with: "%2F")
        guard let manifestURL = URL(string: "https://registry.npmjs.org/\(escaped)/latest"),
              let downloadsURL = URL(string: "https://api.npmjs.org/downloads/point/last-week/\(name)") else { return nil }
        async let manifestData = try? session.data(from: manifestURL).0
        async let downloadsData = try? session.data(from: downloadsURL).0
        guard let manifest = (await manifestData).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }),
              let downloads = (await downloadsData).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["downloads"] as? Int,
              downloads >= minimumDownloads else { return nil }
        let command: String
        if let bin = manifest["bin"] as? [String: Any], let first = bin.keys.sorted().first {
            command = first
        } else if manifest["bin"] is String {
            command = String(name.split(separator: "/").last ?? Substring(name))
        } else {
            return nil // A library, not a tool.
        }
        return DiscoveredTool(package: name, command: command, summary: summary, source: .npm, isInstalled: false, weeklyDownloads: downloads)
    }

    // MARK: - tldr

    /// tldr pages as counted words, to rank them against a request.
    private struct PageIndex {
        struct Page {
            var command: String
            var description: String
            var terms: [String: Int]
            var length: Int
        }
        var pages: [Page] = []
        var documentFrequency: [String: Int] = [:]
        var averageLength = 1.0
    }

    private var pageIndex: PageIndex?

    private func loadedPageIndex() -> PageIndex {
        if let pageIndex { return pageIndex }
        var index = PageIndex()
        for language in ["es", "en"] {
            for platform in ["osx", "common"] {
                let folder = tldrURL.appending(path: "\(language)/\(platform)", directoryHint: .isDirectory)
                for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [] where file.hasSuffix(".md") {
                    guard let text = try? String(contentsOf: folder.appending(path: file), encoding: .utf8) else { continue }
                    let command = String(file.dropLast(3))
                    let page = Self.parse(text, isSpanish: language == "es")
                    // What it does and what each example is for, in words.
                    let words = Self.searchTerms(([command, page.description] + page.examples.map(\.0)).joined(separator: " "))
                    var terms: [String: Int] = [:]
                    for word in words { terms[word, default: 0] += 1 }
                    for word in terms.keys { index.documentFrequency[word, default: 0] += 1 }
                    index.pages.append(.init(command: command, description: page.description, terms: terms, length: words.count))
                }
            }
        }
        index.averageLength = max(1, Double(index.pages.map(\.length).reduce(0, +)) / Double(max(index.pages.count, 1)))
        // Not kept until the pages are there: they arrive after the first download.
        if !index.pages.isEmpty { pageIndex = index }
        return index
    }

    /// Commands this Mac has whose tldr page shares the most telling words
    /// with what was asked (ranked like a search engine, BM25): “¿cuánto
    /// tiempo lleva encendido el Mac?” finds uptime, “force quit” pkill.
    /// `queries` are the request and the model's English keywords.
    func searchPages(_ queries: [String], among executables: Set<String>, limit: Int = 4) -> [(command: String, description: String, score: Double)] {
        let index = loadedPageIndex()
        let wanted = Set(queries.flatMap(Self.searchTerms))
        guard !wanted.isEmpty, !index.pages.isEmpty else { return [] }
        let count = Double(index.pages.count)
        var best: [String: (description: String, score: Double)] = [:]
        for page in index.pages where executables.contains(page.command) {
            var score = 0.0
            for word in wanted {
                guard let frequency = page.terms[word].map(Double.init), let documents = index.documentFrequency[word].map(Double.init) else { continue }
                let rarity = log(1 + (count - documents + 0.5) / (documents + 0.5))
                score += rarity * frequency * 2.2 / (frequency + 1.2 * (0.25 + 0.75 * Double(page.length) / index.averageLength))
            }
            if score > best[page.command]?.score ?? 0 { best[page.command] = (page.description, score) }
        }
        return best.map { (command: $0.key, description: $0.value.description, score: $0.value.score) }
            .sorted { $0.score > $1.score }
            .prefix(limit).map { $0 }
    }

    /// Words for the page search: no accents or filler, cut to their first
    /// five letters so “comprimir” and “comprime” meet.
    static func searchTerms(_ text: String) -> [String] {
        AssistantEngine.normalized(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !searchStopwords.contains($0) }
            .map { String($0.prefix(5)) }
    }

    private static let searchStopwords: Set<String> = [
        "the", "an", "of", "to", "in", "for", "and", "or", "with", "on", "by", "from", "as", "is", "it", "its", "this", "that",
        "all", "be", "into", "using", "use", "given", "specific", "de", "la", "el", "los", "las", "un", "una", "en", "y", "o",
        "con", "por", "para", "del", "al", "que", "se", "su", "sus", "como", "mi", "mis", "este", "esta", "quiero", "hola",
    ]

    /// The tldr page for a command, in Spanish when there is one.
    func examples(for command: String) -> ToolExamples? {
        for language in ["es", "en"] {
            for platform in ["osx", "common"] {
                let url = tldrURL.appending(path: "\(language)/\(platform)/\(command).md")
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                return Self.parse(text, isSpanish: language == "es")
            }
        }
        return nil
    }

    static func parse(_ page: String, isSpanish: Bool) -> ToolExamples {
        var description: [String] = []
        var examples: [(String, String)] = []
        var pending: String?
        for line in page.split(separator: "\n").map(String.init) {
            if line.hasPrefix("> "), !line.contains("http"), !line.lowercased().contains("información") {
                description.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("- ") {
                pending = String(line.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            } else if line.hasPrefix("`"), line.hasSuffix("`"), let what = pending {
                // {{path/to/file}} placeholders become plain words.
                let command = String(line.dropFirst().dropLast()).replacing(/\{\{([^}]*)\}\}/) { $0.1 }
                examples.append((what, command))
                pending = nil
            }
        }
        return ToolExamples(description: description.joined(separator: " "), examples: examples, isSpanish: isSpanish)
    }
}
