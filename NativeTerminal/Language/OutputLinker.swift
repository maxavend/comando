import Foundation

/// Turns the file names that `ls` prints into links to those files.
nonisolated enum OutputLinker {
    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Makes web addresses in any output clickable (they open in the browser).
    static func linkifyURLs(_ output: AttributedString) -> AttributedString {
        let text = String(output.characters)
        guard text.contains("://"), let detector = urlDetector else { return output }
        var result = output
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text) else { continue }
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            let start = result.characters.index(result.startIndex, offsetBy: offset)
            let end = result.characters.index(start, offsetBy: length)
            result[start..<end].link = url
        }
        return result
    }

    /// The first address of a server running on this Mac (dev servers print one).
    static func firstLocalURL(in text: String) -> URL? {
        guard text.contains("://"), let detector = urlDetector else { return nil }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.lazy.compactMap(\.url).first { url in
            ["http", "https"].contains(url.scheme ?? "") && ["localhost", "127.0.0.1", "0.0.0.0", "[::1]"].contains(url.host ?? "")
        }
    }

    /// Characters `ls -F` appends to show the kind of an entry.
    private static let classifySuffixes: Set<Character> = ["/", "*", "@", "=", "|", "%"]

    /// The folder whose contents `command` lists, or nil if it isn't an `ls`.
    static func listedFolder(command: String, directory: String) -> String? {
        let words = ShellEscape.words(command)
        guard ShellSession.firstWord(of: command) == "ls" else { return nil }
        let targets = words.dropFirst().filter { !$0.hasPrefix("-") }
        guard targets.count <= 1 else { return nil }
        guard let target = targets.first else { return directory }
        let expanded = ShellEscape.expandTilde(target)
        let path = expanded.hasPrefix("/") ? expanded : (directory as NSString).appendingPathComponent(expanded)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return (path as NSString).standardizingPath
    }

    /// Adds a file URL link to each name in `output` that exists in `folder`.
    static func linkify(_ output: AttributedString, folder: String) -> AttributedString {
        let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
        guard !entries.isEmpty else { return output }
        var result = output
        let text = String(output.characters)
        var lineStart = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            for (offset, length, name) in names(in: lineText, entries: entries) {
                let start = result.characters.index(result.startIndex, offsetBy: lineStart + offset)
                let end = result.characters.index(start, offsetBy: length)
                result[start..<end].link = URL(filePath: (folder as NSString).appendingPathComponent(name))
            }
            lineStart += lineText.count + 1
        }
        return result
    }

    static func names(in line: String, folder: String) -> [(Int, Int, String)] {
        names(in: line, entries: Set((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []))
    }

    /// Names found in one line of `ls` output, as (character offset, length, name).
    ///
    /// Columns may be separated by a single space (colored `ls`) and names may
    /// contain spaces, so words are joined greedily into the longest run that
    /// matches a real entry of the folder.
    static func names(in line: String, entries: Set<String>) -> [(Int, Int, String)] {
        let characters = Array(line)
        var words: [(start: Int, end: Int)] = []
        var index = 0
        while index < characters.count {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
            let start = index
            while index < characters.count, characters[index] != " ", characters[index] != "\t" { index += 1 }
            if index > start { words.append((start, index)) }
        }

        var found: [(Int, Int, String)] = []
        var first = 0
        while first < words.count {
            var matched = false
            for last in stride(from: words.count - 1, through: first, by: -1) {
                let candidate = String(characters[words[first].start..<words[last].end])
                if let name = entryName(candidate, in: entries) {
                    found.append((words[first].start, words[last].end - words[first].start, name))
                    first = last + 1
                    matched = true
                    break
                }
            }
            if !matched { first += 1 }
        }
        return found
    }

    /// The folder entry `candidate` refers to, allowing `ls -F` suffixes and symlink arrows.
    private static func entryName(_ candidate: String, in entries: Set<String>) -> String? {
        var name = candidate
        if let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
        if entries.contains(name), name != ".", name != ".." { return name }
        if let last = name.last, classifySuffixes.contains(last), name.count > 1 {
            name.removeLast()
            if entries.contains(name) { return name }
        }
        return nil
    }
}
