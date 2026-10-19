import Darwin
import Foundation
import Observation
import SwiftTerm

/// One zsh process running in a pseudo-terminal, with the app's shell
/// integration loaded. Converts the PTY byte stream into command lifecycle
/// events and live output.
@Observable
final class ShellSession {
    enum Phase: Equatable {
        case notStarted
        case starting
        case idle
        case running
        case interactive
        case exited
    }

    let id: UUID
    private(set) var phase: Phase = .notStarted
    private(set) var directory: String
    private(set) var live: LiveOutput?
    /// True while the running program has turned terminal echo off (e.g. a password prompt).
    private(set) var echoDisabled = false

    @ObservationIgnored weak var delegate: ShellSessionDelegate?
    @ObservationIgnored private(set) var pathEntries: [String] = []
    /// First words that should open the embedded terminal right away.
    @ObservationIgnored var interactiveCommands: Set<String> = []

    @ObservationIgnored private var process: LocalProcess?
    @ObservationIgnored private var bridge: ProcessBridge?
    @ObservationIgnored private var parser = StreamParser()
    @ObservationIgnored private var queued: (UUID, String)?
    @ObservationIgnored private var outputStarted = false
    @ObservationIgnored private var preOutput: [UInt8] = []
    @ObservationIgnored private var chatSize = (columns: 100, rows: 40)
    @ObservationIgnored private var echoTask: Task<Void, Never>?

    // Embedded terminal plumbing.
    @ObservationIgnored private var interactiveBacklog: [UInt8] = []
    @ObservationIgnored private var interactiveSink: ((ArraySlice<UInt8>) -> Void)?
    @ObservationIgnored var transcriptProvider: (() -> String?)?

    init(id: UUID, directory: String) {
        self.id = id
        self.directory = directory
    }

    isolated deinit {
        echoTask?.cancel()
        process?.terminate()
    }

    // MARK: - Lifecycle

    func start() {
        guard phase == .notStarted || phase == .exited else { return }
        let bridge = ProcessBridge(session: self)
        let process = LocalProcess(delegate: bridge)
        self.bridge = bridge
        self.process = process
        parser = StreamParser()
        phase = .starting

        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) || !isDirectory.boolValue {
            directory = NSHomeDirectory()
        }
        process.startProcess(
            executable: "/bin/zsh",
            args: [],
            environment: ShellIntegration.environment(),
            execName: "-zsh",
            currentDirectory: directory
        )
        applyWindowSize(columns: chatSize.columns, rows: chatSize.rows)
    }

    func terminate() {
        process?.terminate()
    }

    func restart() {
        process?.terminate()
        process = nil
        bridge = nil
        if live != nil { finishCurrent(exitCode: nil) }
        phase = .notStarted
        start()
    }

    var isBusy: Bool { phase == .running || phase == .interactive }

    // MARK: - Input

    /// Runs `command` as a new command line.
    func run(_ command: String, entryID: UUID) {
        switch phase {
        case .notStarted, .exited:
            queued = (entryID, command)
            start()
            return
        case .starting:
            queued = (entryID, command)
            return
        case .running, .interactive:
            return
        case .idle:
            break
        }
        live = LiveOutput(entryID: entryID, command: command, screenRows: chatSize.rows)
        outputStarted = false
        preOutput = []
        phase = .running
        // Bracketed paste lets multi-line commands and special characters reach
        // zle untouched; the trailing CR accepts the line.
        var bytes: [UInt8] = Array("\u{1B}[200~".utf8)
        bytes += Array(command.utf8)
        bytes += Array("\u{1B}[201~\r".utf8)
        send(bytes)
        startEchoMonitoring()
    }

    /// Sends a line of input to the running program (stdin).
    func sendLine(_ text: String) {
        send(Array((text + "\r").utf8))
    }

    /// Sends a message to a program that reads keys one by one (an AI agent's
    /// prompt): the text first, then Return on its own, so the program sees a
    /// key press instead of a pasted line break.
    func sendMessage(_ text: String) {
        send(Array(text.utf8))
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            send([0x0D])
        }
    }

    func sendRaw<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        send(Array(bytes))
    }

    func interrupt() { send([0x03]) }

    /// Quits the running program, gently first: ⌃C twice (what agents and
    /// most programs expect), then ⌃D, and only then a signal to its process
    /// group. The shell itself stays.
    func quitForeground() {
        guard isBusy else { return }
        interrupt()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.isBusy else { return }
            self.interrupt()
            try? await Task.sleep(for: .seconds(1.2))
            guard self.isBusy else { return }
            self.sendEOF()
            try? await Task.sleep(for: .seconds(1.5))
            guard self.isBusy else { return }
            self.signalForeground(SIGTERM)
            try? await Task.sleep(for: .seconds(2))
            if self.isBusy { self.signalForeground(SIGKILL) }
        }
    }

    /// The program in the terminal's foreground, never the shell.
    private func signalForeground(_ signal: Int32) {
        guard let process, process.childfd >= 0 else { return }
        let group = tcgetpgrp(process.childfd)
        guard group > 0, group != process.shellPid else { return }
        killpg(group, signal)
    }
    func sendEOF() { send([0x04]) }

    private func send(_ bytes: [UInt8]) {
        guard let process, process.running else { return }
        process.send(data: bytes[...])
    }

    // MARK: - Window size

    /// Size used while output is shown as chat bubbles.
    func setChatSize(columns: Int, rows: Int) {
        let columns = max(20, columns)
        guard chatSize != (columns, rows) else { return }
        chatSize = (columns, rows)
        if phase != .interactive {
            applyWindowSize(columns: columns, rows: rows)
        }
    }

    fileprivate var chatWindowSize: (columns: Int, rows: Int) { chatSize }

    func applyWindowSize(columns: Int, rows: Int) {
        guard let fd = process?.childfd, fd >= 0 else { return }
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(fd, TIOCSWINSZ, &size)
    }

    // MARK: - Embedded terminal

    /// Connects the embedded terminal view. Bytes received before it attached
    /// are replayed so the program's first screen isn't lost.
    func attachInteractiveSink(_ sink: @escaping (ArraySlice<UInt8>) -> Void) {
        interactiveSink = sink
        if !interactiveBacklog.isEmpty {
            sink(interactiveBacklog[...])
            interactiveBacklog = []
        }
    }

    func detachInteractiveSink() {
        interactiveSink = nil
    }

    /// Switches the running command to the embedded terminal.
    func openInTerminal() {
        guard phase == .running, let live else { return }
        enterInteractive(replaying: live.raw)
    }

    private func enterInteractive(replaying bytes: [UInt8]) {
        guard let live else { return }
        phase = .interactive
        live.isInteractive = true
        echoDisabled = false
        interactiveBacklog = bytes
    }

    // MARK: - Output handling

    fileprivate func receive(_ bytes: ArraySlice<UInt8>) {
        for parsed in parser.feed(bytes) {
            if case .osc(let payload) = parsed.token, handleIntegration(payload) {
                continue
            }
            switch phase {
            case .running:
                guard let live else { continue }
                guard outputStarted else {
                    preOutput.append(contentsOf: parsed.raw)
                    continue
                }
                if case .csi(let csi) = parsed.token, Self.entersAlternateScreen(csi) {
                    enterInteractive(replaying: parsed.raw)
                    continue
                }
                live.append(parsed)
            case .interactive:
                if let interactiveSink {
                    interactiveSink(parsed.raw[...])
                } else {
                    interactiveBacklog.append(contentsOf: parsed.raw)
                }
            default:
                break
            }
        }
    }

    /// Handles the shell integration OSCs. Returns false for any other OSC.
    private func handleIntegration(_ payload: String) -> Bool {
        if payload.hasPrefix("133;") {
            let parts = payload.split(separator: ";", omittingEmptySubsequences: false)
            switch parts.count > 1 ? parts[1] : "" {
            case "A":
                promptReady()
            case "C":
                outputStarted = true
                // AI agents ask questions with arrow-key menus even before
                // they take the full screen, so they always get the terminal.
                if let live, interactiveCommands.contains(Self.firstWord(of: live.command)) || AICommandLine.isAgent(live.command) {
                    enterInteractive(replaying: [])
                }
            case "D":
                let code = parts.count > 2 ? Int32(parts[2]) : nil
                if isBusy { finishCurrent(exitCode: code) }
            default:
                break
            }
            return true
        }
        if payload.hasPrefix("7;") {
            updateDirectory(fromFileURL: String(payload.dropFirst(2)))
            return true
        }
        if payload.hasPrefix(ShellIntegration.pathOSC) {
            pathEntries = payload.dropFirst(ShellIntegration.pathOSC.count)
                .split(separator: ":")
                .map(String.init)
            return true
        }
        return false
    }

    private func promptReady() {
        if phase == .starting {
            phase = .idle
        }
        if phase == .idle, let (entryID, command) = queued {
            queued = nil
            run(command, entryID: entryID)
        }
    }

    private func updateDirectory(fromFileURL value: String) {
        // file://host/path — the path is sent raw (not percent-encoded).
        guard value.hasPrefix("file://") else { return }
        let rest = value.dropFirst("file://".count)
        guard let slash = rest.firstIndex(of: "/") else { return }
        let path = String(rest[slash...])
        guard path != directory else { return }
        directory = path
        delegate?.shellSession(self, didChangeDirectory: path)
    }

    private func finishCurrent(exitCode: Int32?) {
        guard let live else { return }
        let wasInteractive = live.isInteractive
        var output = live.raw
        if !outputStarted {
            // No preexec: the line failed to parse. zle disables bracketed paste
            // (ESC[?2004l) when it accepts the line; the error follows it.
            output = Self.bytesAfterLineAccepted(preOutput)
        }
        var transcript: String?
        if wasInteractive, let text = transcriptProvider?()?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            transcript = text
        }
        let result = CommandResult(
            entryID: live.entryID,
            exitCode: exitCode,
            output: output,
            truncated: live.truncated,
            wasInteractive: wasInteractive,
            transcript: transcript,
            finishedAt: .now
        )
        self.live = nil
        echoTask?.cancel()
        echoDisabled = false
        interactiveSink = nil
        interactiveBacklog = []
        preOutput = []
        if phase != .exited { phase = .idle }
        applyWindowSize(columns: chatSize.columns, rows: chatSize.rows)
        delegate?.shellSession(self, didFinish: result)
    }

    fileprivate func processTerminated() {
        if live != nil {
            finishCurrent(exitCode: 0)
        }
        phase = .exited
        echoTask?.cancel()
        delegate?.shellSessionDidExit(self)
    }

    // MARK: - Echo (password prompt) detection

    private func startEchoMonitoring() {
        echoTask?.cancel()
        echoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                guard self.phase == .running, let fd = self.process?.childfd, fd >= 0 else { continue }
                var attributes = termios()
                guard tcgetattr(fd, &attributes) == 0 else { continue }
                // Echo off while still in line mode is what password prompts look like.
                let echoOff = attributes.c_lflag & tcflag_t(ECHO) == 0
                let canonical = attributes.c_lflag & tcflag_t(ICANON) != 0
                let disabled = echoOff && canonical && self.outputStarted
                if self.echoDisabled != disabled { self.echoDisabled = disabled }
            }
        }
    }

    // MARK: - Helpers

    nonisolated static func entersAlternateScreen(_ csi: CSISequence) -> Bool {
        guard csi.marker == UInt8(ascii: "?"), csi.final == UInt8(ascii: "h") else { return false }
        return csi.params.contains { [47, 1047, 1049].contains($0) }
    }

    nonisolated static func firstWord(of command: String) -> String {
        let trimmed = command.drop { $0 == " " }
        let word = trimmed.prefix { $0 != " " && $0 != "\n" }
        return String(word.split(separator: "/").last ?? word[...])
    }

    nonisolated static func bytesAfterLineAccepted(_ bytes: [UInt8]) -> [UInt8] {
        let marker = Array("\u{1B}[?2004l".utf8)
        guard bytes.count >= marker.count else { return [] }
        var index = bytes.count - marker.count
        while index >= 0 {
            if Array(bytes[index..<(index + marker.count)]) == marker {
                var rest = Array(bytes[(index + marker.count)...])
                while let first = rest.first, first == 0x0D || first == 0x0A { rest.removeFirst() }
                return rest
            }
            index -= 1
        }
        return []
    }
}

/// Receives callbacks from SwiftTerm's `LocalProcess` (delivered on the main
/// queue) and forwards them to the main-actor `ShellSession`.
private nonisolated final class ProcessBridge: LocalProcessDelegate, @unchecked Sendable {
    private weak var session: ShellSession?

    @MainActor init(session: ShellSession) {
        self.session = session
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        MainActor.assumeIsolated {
            session?.processTerminated()
        }
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        MainActor.assumeIsolated {
            session?.receive(slice)
        }
    }

    func getWindowSize() -> winsize {
        let size = MainActor.assumeIsolated { session?.chatWindowSize ?? (columns: 100, rows: 40) }
        return winsize(ws_row: UInt16(clamping: size.rows), ws_col: UInt16(clamping: size.columns), ws_xpixel: 0, ws_ypixel: 0)
    }
}
