import Foundation
import Testing
@testable import NativeTerminal

/// Runs real commands through zsh with the user's configuration and the app's
/// shell integration loaded.
@MainActor
@Suite(.serialized)
final class ShellIntegrationTests: ShellSessionDelegate {
    private var results: [CommandResult] = []
    private var directories: [String] = []
    private let shell: ShellSession

    init() async throws {
        try ShellIntegration.install()
        shell = ShellSession(id: UUID(), directory: NSHomeDirectory())
        shell.delegate = self
        shell.start()
        try await waitUntil { self.shell.phase == .idle }
    }

    isolated deinit {
        shell.terminate()
    }

    func shellSession(_ session: ShellSession, didChangeDirectory directory: String) {
        directories.append(directory)
    }

    func shellSession(_ session: ShellSession, didFinish result: CommandResult) {
        results.append(result)
    }

    func shellSessionDidExit(_ session: ShellSession) {}

    private func waitUntil(timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out (phase: \(shell.phase))")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func run(_ command: String) async throws -> (code: Int32?, text: String, result: CommandResult) {
        let count = results.count
        shell.run(command, entryID: UUID())
        try await waitUntil { self.results.count > count && self.shell.phase == .idle }
        let result = results[count]
        return (result.exitCode, OutputRenderer.plainText(raw: result.output), result)
    }

    @Test func echoProducesOutputAndSuccess() async throws {
        let (code, text, _) = try await run("echo hola")
        #expect(code == 0)
        #expect(text == "hola")
    }

    @Test func failingCommandReportsExitCode() async throws {
        let (code, text, _) = try await run("false")
        #expect(code == 1)
        #expect(text.isEmpty)
    }

    @Test func multiLineCommand() async throws {
        let (code, text, _) = try await run("for i in 1 2 3; do\n  echo \"línea $i\"\ndone")
        #expect(code == 0)
        #expect(text == "línea 1\nlínea 2\nlínea 3")
    }

    @Test func changingDirectoryIsReported() async throws {
        let (code, _, _) = try await run("cd /usr/bin")
        #expect(code == 0)
        try await waitUntil { self.shell.directory == "/usr/bin" }
        #expect(directories.last == "/usr/bin")
    }

    @Test func colorsArePreservedInRawOutput() async throws {
        let (_, text, result) = try await run("printf '\\033[31mrojo\\033[0m\\n'")
        #expect(text == "rojo")
        #expect(String(decoding: result.output, as: UTF8.self).contains("\u{1B}[31m"))
    }

    @Test func parseErrorIsShown() async throws {
        let (code, text, _) = try await run("echo )")
        #expect(code != 0)
        #expect(text.contains("parse error"))
    }

    @Test func pathIsReportedForCompletion() async throws {
        try await waitUntil { !self.shell.pathEntries.isEmpty }
        #expect(shell.pathEntries.contains("/bin"))
    }

    @Test func alternateScreenSwitchesToInteractive() async throws {
        let count = results.count
        shell.run("printf '\\033[?1049h'; sleep 0.3; printf '\\033[?1049l'", entryID: UUID())
        try await waitUntil { self.shell.phase == .interactive }
        try await waitUntil { self.results.count > count }
        #expect(results[count].wasInteractive)
    }
}
