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
        var result = output
        let text = String(output.characters)
        var lineStart = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            for (offset, length, name) in names(in: lineText, folder: folder) {
                let start = result.characters.index(result.startIndex, offsetBy: lineStart + offset)
                let end = result.characters.index(start, offsetBy: length)
                let url = URL(filePath: (folder as NSString).appendingPathComponent(name))
                result[start..<end].link = url
            }
            lineStart += lineText.count + 1
        }
        return result
    }

    /// File names found in one line of `ls` output, as (character offset, length, name).
    static func names(in line: String, folder: String) -> [(Int, Int, String)] {
        let characters = Array(line)
        var found: [(Int, Int, String)] = []

        // Columns are separated by two or more spaces (or tabs).
        var segments: [(start: Int, end: Int)] = []
        var index = 0
        while index < characters.count {
            while index < characters.count, characters[index] == " " || characters[index] == "\t" { index += 1 }
            let start = index
            while index < characters.count {
                if characters[index] == "\t" { break }
                if characters[index] == " ", index + 1 < characters.count, characters[index + 1] == " " { break }
                index += 1
            }
            var end = index
            while end > start, characters[end - 1] == " " { end -= 1 }
            if end > start { segments.append((start, end)) }
        }

        for segment in segments {
            if let match = existingName(characters[segment.start..<segment.end], folder: folder) {
                found.append((segment.start, segment.end - segment.start, match))
            }
        }
        if !found.isEmpty { return found }

        // `ls -l`: the name is the end of the line, after the date.
        var wordStarts: [Int] = []
        for position in characters.indices where characters[position] != " " && (position == 0 || characters[position - 1] == " ") {
            wordStarts.append(position)
        }
        for start in wordStarts.dropFirst() {
            if let match = existingName(characters[start...], folder: folder) {
                return [(start, characters.count - start, match)]
            }
        }
        return []
    }

    private static func existingName(_ characters: ArraySlice<Character>, folder: String) -> String? {
        var name = String(characters).trimmingCharacters(in: .whitespaces)
        if let last = name.last, classifySuffixes.contains(last), name.count > 1 { name.removeLast() }
        // Symlinks in `ls -l` read “name -> target”.
        if let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        let path = (folder as NSString).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: path) ? name : nil
    }
}
