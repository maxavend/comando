import Foundation

/// Reads progress (“45%”, “12/80”) from the line a command keeps rewriting.
nonisolated enum ProgressParser {
    struct Progress: Equatable, Sendable {
        var fraction: Double
        /// The line without bar drawings, e.g. “Descargando paquete… 45%”.
        var label: String
    }

    static func parse(_ line: String) -> Progress? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var fraction: Double?
        if let match = text.firstMatch(of: /(\d{1,3}(?:[.,]\d+)?)\s?%/),
           let value = Double(match.1.replacing(",", with: ".")), value <= 100 {
            fraction = value / 100
        } else if let match = text.firstMatch(of: /\b(\d+)\s?\/\s?(\d+)\b/),
                  let done = Double(match.1), let total = Double(match.2), total > 0, done <= total,
                  text.contains("[") || text.lowercased().contains("progress") {
            fraction = done / total
        }
        guard let fraction else { return nil }
        // Drop bar drawings like [=====>    ] or ████░░░.
        let label = text
            .replacing(/\[[=#>\-\s.*]+\]/, with: "")
            .replacing(/[█▉▊▋▌▍▎▏░▒▓■□━─]+/, with: "")
            .replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: .whitespaces)
        return Progress(fraction: fraction, label: label)
    }
}
