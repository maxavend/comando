import Foundation

/// An agent CLI running headless: lines it prints go to `onLine`, and
/// `onExit` reports how it ended with the end of its error output.
nonisolated final class AgentProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var errorTail = Data()

    var isRunning: Bool { process.isRunning }

    /// The CLI's full path in the shell's `$PATH`, or nil when it isn't installed.
    static func executable(_ name: String, path: [String]) -> String? {
        let folders = path.isEmpty ? ToolInventory.defaultPath.split(separator: ":").map(String.init) : path
        return folders.lazy.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    init(executable: String, arguments: [String], directory: String, path: [String],
         onLine: @escaping @Sendable (String) -> Void,
         onExit: @escaping @Sendable (Int32, String) -> Void) throws {
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ToolInventory.searchPath(path)
        // Plain output: no colors or spinners meant for a terminal.
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        environment["CI"] = nil
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            for line in self.lines(from: data) { onLine(line) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.lock.withLock {
                self.errorTail.append(data)
                if self.errorTail.count > 4096 { self.errorTail = self.errorTail.suffix(4096) }
            }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.output.fileHandleForReading.readabilityHandler = nil
            self.errors.fileHandleForReading.readabilityHandler = nil
            // Whatever was left without a final line break.
            let rest = self.output.fileHandleForReading.readDataToEndOfFile()
            for line in self.lines(from: rest, flush: true) { onLine(line) }
            let tail = self.lock.withLock { String(decoding: self.errorTail, as: UTF8.self) }
            onExit(process.terminationStatus, tail)
        }
        try process.run()
    }

    private func lines(from data: Data, flush: Bool = false) -> [String] {
        lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let end = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<end], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...end)
            }
            if flush, !buffer.isEmpty {
                lines.append(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll()
            }
            return lines
        }
    }

    func write(_ text: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    }

    /// No more messages: a persistent CLI finishes its turn and quits.
    func closeInput() {
        try? input.fileHandleForWriting.close()
    }

    func stop() {
        guard process.isRunning else { return }
        process.interrupt()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning { process.terminate() }
        }
    }
}
