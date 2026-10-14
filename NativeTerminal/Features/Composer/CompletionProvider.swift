import Foundation

struct Completion: Identifiable, Hashable {
    enum Kind: Hashable {
        case history
        case command
        case directory
        case file
    }

    var title: String
    /// The whole command line after accepting this completion.
    var completion: String
    var kind: Kind

    var id: String { completion }

    var systemImage: String {
        switch kind {
        case .history: "clock.arrow.circlepath"
        case .command: "apple.terminal"
        case .directory: "folder"
        case .file: "doc"
        }
    }
}

/// Suggests history, executables and paths for the command being typed.
final class CompletionProvider {
    private static let builtins = [
        "alias", "bg", "cd", "echo", "exit", "export", "fg", "history", "jobs", "popd",
        "pushd", "pwd", "source", "type", "unalias", "unset", "which",
    ]
    private static let directoryCommands: Set<String> = ["cd", "pushd", "rmdir"]

    private var executables: (path: [String], names: [String]) = ([], [])
    private var listings: [String: (date: Date, entries: [(name: String, isDirectory: Bool)])] = [:]

    func suggestions(
        for text: String,
        directory: String,
        pathEntries: [String],
        history: [String],
        limit: Int = 8
    ) -> [Completion] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !text.contains("\n") else { return [] }

        var results: [Completion] = []
        var seen: Set<String> = []
        func add(_ completion: Completion) {
            guard completion.completion != text, seen.insert(completion.completion).inserted else { return }
            results.append(completion)
        }

        for command in history.reversed() where command.hasPrefix(text) {
            add(Completion(title: command, completion: command, kind: .history))
            if results.count >= 3 { break }
        }
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
        if executables.path != pathEntries || executables.names.isEmpty {
            var names = Set(Self.builtins)
            for folder in pathEntries {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
                names.formUnion(items)
            }
            executables = (pathEntries, Array(names))
        }
        return executables.names
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
