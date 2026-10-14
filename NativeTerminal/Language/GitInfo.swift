import Foundation

/// The Git state of a folder: branch and number of changed files.
nonisolated struct GitInfo: Equatable, Sendable {
    var branch: String
    var changes: Int

    /// Parses `git status --porcelain --branch`.
    static func parse(porcelain: String) -> GitInfo? {
        let lines = porcelain.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first, header.hasPrefix("## ") else { return nil }
        var branch = String(header.dropFirst(3))
        if branch.hasPrefix("No commits yet on ") { branch = String(branch.dropFirst("No commits yet on ".count)) }
        if let dots = branch.range(of: "...") { branch = String(branch[..<dots.lowerBound]) }
        if let space = branch.firstIndex(of: " ") { branch = String(branch[..<space]) }
        return GitInfo(branch: branch, changes: lines.count - 1)
    }

    /// Reads the state of `directory`, or nil if it isn't inside a repository.
    @concurrent
    static func read(in directory: String) async -> GitInfo? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory, "status", "--porcelain", "--branch"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(porcelain: String(decoding: data, as: UTF8.self))
    }
}
