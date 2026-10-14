import AppKit
import SwiftUI

/// The result of rendering a command's output, ready to display.
nonisolated struct RenderedOutput: Sendable {
    /// The tail of the output shown in the bubble.
    var preview: AttributedString
    /// Number of lines in the whole output (after trimming).
    var totalLines: Int
    /// Number of lines included in `preview`.
    var previewLines: Int
    var plainText: String
    /// Output whose columns line up with spaces (ls, tables), which needs a
    /// monospaced font to stay readable.
    var isTabular: Bool = false

    var isEmpty: Bool { totalLines == 0 }
    var isClipped: Bool { previewLines < totalLines }

    static let empty = RenderedOutput(preview: AttributedString(), totalLines: 0, previewLines: 0, plainText: "")
}
