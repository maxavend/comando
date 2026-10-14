import Foundation
import Observation

/// Output of the command that is currently running, observed by its bubble.
@Observable
final class LiveOutput {
    let entryID: UUID
    let command: String
    let startedAt: Date

    /// Bumped (at most ~10 times per second) when `buffer` changes.
    private(set) var version = 0
    private(set) var hasOutput = false
    var isInteractive = false

    @ObservationIgnored var buffer = LineBuffer()
    @ObservationIgnored var raw: [UInt8] = []
    @ObservationIgnored var truncated = false
    @ObservationIgnored private var updateScheduled = false

    static let rawLimit = 1 << 20

    init(entryID: UUID, command: String, startedAt: Date = .now, screenRows: Int) {
        self.entryID = entryID
        self.command = command
        self.startedAt = startedAt
        buffer.screenRows = screenRows
    }

    func append(_ token: ParsedToken) {
        buffer.apply(token.token)
        raw.append(contentsOf: token.raw)
        if raw.count > Self.rawLimit * 2 {
            // Keep the most recent output, like a terminal's scrollback.
            raw.removeFirst(raw.count - Self.rawLimit)
            truncated = true
        }
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.publishUpdate()
        }
    }

    private func publishUpdate() {
        updateScheduled = false
        version &+= 1
        if !hasOutput, !buffer.isEmpty { hasOutput = true }
    }
}
