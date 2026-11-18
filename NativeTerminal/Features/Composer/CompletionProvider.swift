import Foundation

/// Suggests history, executables and paths for the command being typed.
final class CompletionProvider {
    private static let directoryCommands: Set<String> = ["cd", "pushd", "rmdir"]

    private var listings: [String: (date: Date, entries: [(name: String, isDirectory: Bool)])] = [:]

    func suggestions(
        for text: String,
        directory: String,
        pathEntries: [String],
        history: [String],
        limit: Int = 8,
        contextual: [Completion] = []
    ) -> [Completion] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !text.contains("\n") else { return [] }

        var results: [Completion] = []
        var seen: Set<String> = []
        func add(_ completion: Completion) {
            guard results.count < limit, completion.completion != text, seen.insert(completion.completion).inserted else { return }
            results.append(completion)
        }

        for completion in contextual { add(completion) }
        if !results.isEmpty { return results }
        var historyCount = 0
        for command in history.reversed() where command.hasPrefix(text) {
            let countBefore = results.count
            add(Completion(title: command, completion: command, kind: .history))
            historyCount += results.count - countBefore
            if historyCount >= 3 || results.count >= limit { break }
        }
        guard results.count < limit else { return results }
        for completion in wordCompletions(for: text, directory: directory, pathEntries: pathEntries) {
            add(completion)
            if results.count >= limit { break }
        }
        return results
    }

    /// The text after pressing Tab: the single match, or the longest common prefix.
    func tabCompletion(for text: String, directory: String, pathEntries: [String]) -> String? {
        let matches = wordCompletions(for: text, directory: directory, pathEntries: pathEntries)
        guard let first = matches.first else { return nil }
        if matches.count == 1 { return first.completion }
        var prefix = first.completion
        for match in matches.dropFirst() {
            prefix = String(prefix.commonPrefix(with: match.completion))
        }
        return prefix.count > text.count ? prefix : nil
    }

    // MARK: - Words

    private func wordCompletions(for text: String, directory: String, pathEntries: [String]) -> [Completion] {
        let (head, word) = Self.splitLastWord(text)
        let isFirstWord = head.trimmingCharacters(in: .whitespaces).isEmpty
        let firstWord = head.split(separator: " ").first.map(String.init) ?? ""

        if isFirstWord && !word.contains("/") && !word.hasPrefix("~") && !word.hasPrefix(".") {
            guard !word.isEmpty else { return [] }
            return commandNames(pathEntries: pathEntries)
                .filter { $0.hasPrefix(word) && $0 != word }
                .sorted { ($0.count, $0) < ($1.count, $1) }
                .prefix(8)
                .map { Completion(title: $0, completion: head + $0 + " ", kind: .command) }
        }
        let onlyDirectories = Self.directoryCommands.contains(firstWord)
        return pathCompletions(head: head, word: word, directory: directory, onlyDirectories: onlyDirectories)
    }

    private func pathCompletions(head: String, word: String, directory: String, onlyDirectories: Bool) -> [Completion] {
        let unescaped = ShellEscape.removeBackslashes(word)
        let slash = unescaped.lastIndex(of: "/")
        let folderPart = slash.map { String(unescaped[...$0]) } ?? ""
        let namePrefix = slash.map { String(unescaped[unescaped.index(after: $0)...]) } ?? unescaped

        let expanded = ShellEscape.expandTilde(folderPart)
        let base: String
        if expanded.isEmpty {
            base = directory
        } else if expanded.hasPrefix("/") {
            base = expanded
        } else {
            base = (directory as NSString).appendingPathComponent(expanded)
        }

        let showHidden = namePrefix.hasPrefix(".")
        let matches = listing(of: base)
            .filter { entry in
                (showHidden || !entry.name.hasPrefix("."))
                    && (!onlyDirectories || entry.isDirectory)
                    && entry.name.lowercased().hasPrefix(namePrefix.lowercased())
                    && entry.name != namePrefix
            }
            .sorted { lhs, rhs in
                // Exact-case matches first, then folders, then alphabetical.
                let lhsExact = lhs.name.hasPrefix(namePrefix), rhsExact = rhs.name.hasPrefix(namePrefix)
                if lhsExact != rhsExact { return lhsExact }
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(8)

        let escapedFolder = ShellEscape.addBackslashes(folderPart)
        return matches.map { entry in
            let suffix = entry.isDirectory ? "/" : " "
            return Completion(
                title: entry.name + (entry.isDirectory ? "/" : ""),
                completion: head + escapedFolder + ShellEscape.addBackslashes(entry.name) + suffix,
                kind: entry.isDirectory ? .directory : .file
            )
        }
    }

    private func commandNames(pathEntries: [String]) -> [String] {
        ExecutableIndex.shared.names(for: pathEntries)
    }

    private func listing(of folder: String) -> [(name: String, isDirectory: Bool)] {
        if let cached = listings[folder], cached.date.timeIntervalSinceNow > -2 {
            return cached.entries
        }
        let url = URL(filePath: folder, directoryHint: .isDirectory)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        let entries = contents.map { item in
            (name: item.lastPathComponent, isDirectory: (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }
        listings[folder] = (.now, entries)
        return entries
    }

    /// Splits `git checkout ma` into (`git checkout `, `ma`), honoring `\ ` escapes.
    static func splitLastWord(_ text: String) -> (head: String, word: String) {
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            if text[previous] == " " {
                let escaped = previous > text.startIndex && text[text.index(before: previous)] == "\\"
                if !escaped { break }
            }
            index = previous
        }
        return (String(text[..<index]), String(text[index...]))
    }
}

/// Completions for simple shell commands. Lookups read local metadata without
/// executing the draft or depending on interactive shell configuration.
nonisolated struct ContextualCompletion: Sendable {
    enum Source: Equatable, Sendable {
        case choices([String], Completion.Kind)
        case branches, scripts, processes
    }

    let head: String
    let prefix: String
    let source: Source

    private static let gitOptions = [
        "status": ["--short", "--branch", "--porcelain", "--untracked-files"],
        "log": ["--oneline", "--graph", "--all", "--decorate", "--stat", "--max-count"],
        "diff": ["--staged", "--cached", "--stat", "--name-only", "--name-status"],
        "add": ["--all", "--update", "--patch", "--dry-run"],
        "commit": ["--message", "--amend", "--no-edit", "--all", "--signoff"],
        "switch": ["--create", "--detach", "--track", "--guess"],
        "checkout": ["--branch", "--detach", "--track", "--ours", "--theirs"],
        "branch": ["--all", "--list", "--delete", "--move", "--show-current", "--merged"],
        "fetch": ["--all", "--prune", "--tags", "--dry-run"],
        "pull": ["--rebase", "--ff-only", "--no-rebase", "--autostash"],
        "push": ["--set-upstream", "--force-with-lease", "--dry-run", "--tags"]
    ]

    private static let npmOptions = [
        "install": ["--save-dev", "--save-exact", "--global", "--ignore-scripts", "--dry-run"],
        "uninstall": ["--global", "--dry-run", "--ignore-scripts"],
        "run": ["--if-present", "--silent", "--workspace", "--workspaces"],
        "test": ["--if-present", "--silent", "--workspace", "--workspaces"],
        "exec": ["--package", "--call", "--yes", "--workspace"],
        "ci": ["--ignore-scripts", "--omit", "--include", "--dry-run"],
        "publish": ["--dry-run", "--tag", "--access", "--registry", "--workspace"]
    ]

    @MainActor
    init?(text: String) {
        // Leave shell expressions, quoted input and multiline commands to the
        // regular composer. A completion must belong to the command it edits.
        guard !text.contains(where: { "\n\r\t'\"\\`$;&|<>()#".contains($0) }) else { return nil }
        let (head, prefix) = CompletionProvider.splitLastWord(text)
        let words = ShellEscape.words(head)
        guard let command = words.first, !words.contains("--") else { return nil }

        let source: Source
        switch command {
        case "git", "npm":
            let options = command == "git" ? Self.gitOptions : Self.npmOptions
            if words.count == 1 {
                source = .choices(options.keys.sorted(), .subcommand)
            } else if prefix.hasPrefix("-") {
                guard let choices = options[words[1]] else { return nil }
                source = .choices(choices, .option)
            } else if words == ["npm", "run"] {
                source = .scripts
            } else if [["git", "switch"], ["git", "checkout"], ["git", "branch", "-d"],
                       ["git", "branch", "-D"], ["git", "branch", "--delete"]].contains(words),
                      !prefix.contains("/") || prefix.first?.isLetter == true {
                source = .branches
            } else {
                return nil
            }
        case "kill":
            if words.count == 1, prefix.hasPrefix("-") {
                source = .choices(["-TERM", "-INT", "-HUP", "-KILL", "-QUIT", "-STOP", "-CONT"], .signal)
            } else {
                guard prefix.first.map({ "123456789".contains($0) }) == true,
                      prefix.allSatisfy({ "0123456789".contains($0) }),
                      words.dropFirst().enumerated().allSatisfy({ index, word in
                          Int(word).map { $0 > 0 } == true || (index == 0 && word.hasPrefix("-") && word != "-s")
                      }) else { return nil }
                source = .processes
            }
        default:
            return nil
        }
        self.head = head
        self.prefix = prefix
        self.source = source
    }

    var staticMatches: [Completion] {
        guard case let .choices(values, kind) = source else { return [] }
        return matches(values, kind: kind)
    }

    var needsLookup: Bool {
        if case .choices = source { return false }
        return true
    }

    @concurrent
    func lookup(in directory: String) async -> [Completion] {
        guard !Task.isCancelled else { return [] }
        switch source {
        case .choices:
            return staticMatches
        case .branches:
            let lines = Self.readLines("/usr/bin/git", [
                "--no-optional-locks", "-C", directory, "for-each-ref",
                "--format=%(refname:strip=2)", "refs/heads/"
            ])
            return matches(lines, kind: .branch)
        case .scripts:
            return matches(Self.packageScripts(in: directory), kind: .script)
        case .processes:
            return processMatches(Self.readLines("/bin/ps", ["-axo", "uid=,pid=,ucomm="]),
                                  uid: getuid(), excluding: ProcessInfo.processInfo.processIdentifier)
        }
    }

    private func matches(_ values: [String], kind: Completion.Kind) -> [Completion] {
        values.filter { !$0.isEmpty && $0.hasPrefix(prefix) && !$0.contains(where: \.isNewline) }
            .sorted()
            .prefix(8)
            .map { Completion(title: $0, completion: head + ShellEscape.quote($0) + " ", kind: kind) }
    }

    func processMatches(_ lines: [String], uid: UInt32, excluding excludedPID: Int32) -> [Completion] {
        lines.compactMap { line -> (pid: Int32, name: String)? in
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3, UInt32(fields[0]) == uid,
                  let pid = Int32(fields[1]), pid > 0, pid != excludedPID,
                  fields[1].hasPrefix(prefix) else { return nil }
            return (pid, (String(fields[2]).trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent)
        }
        .sorted { $0.pid < $1.pid }
        .prefix(8)
        .map { Completion(title: "\($0.pid) · \($0.name)", completion: head + "\($0.pid) ", kind: .process) }
    }

    private static func packageScripts(in directory: String) -> [String] {
        let files = FileManager.default
        var folder = URL(filePath: directory, directoryHint: .isDirectory).standardizedFileURL
        while !Task.isCancelled {
            let manifest = folder.appending(path: "package.json")
            if files.fileExists(atPath: manifest.path(percentEncoded: false)) {
                guard let attributes = try? manifest.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      attributes.isRegularFile == true, let size = attributes.fileSize, size <= 2_000_000,
                      let data = try? Data(contentsOf: manifest),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let scripts = json["scripts"] as? [String: String] else { return [] }
                return scripts.keys.filter { !$0.hasPrefix("-") }
            }
            let parent = folder.deletingLastPathComponent()
            guard parent.path != folder.path, folder.path != "/" else { break }
            folder = parent
        }
        return []
    }

    private static func readLines(_ executable: String, _ arguments: [String]) -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
    }
}
