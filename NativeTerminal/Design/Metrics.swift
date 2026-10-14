import AppKit
import SwiftUI

/// Shared layout constants, so every screen lines up on the same grid.
nonisolated enum Metrics {
    // MARK: Chat

    /// Horizontal inset shared by the chat transcript and the composer.
    static let contentInset: CGFloat = 20
    /// Vertical inset at the top and bottom of the transcript.
    static let transcriptVerticalInset: CGFloat = 16
    /// Space between one exchange (command + reply) and the next.
    static let exchangeSpacing: CGFloat = 16
    /// Space between a command bubble and its reply.
    static let replySpacing: CGFloat = 6
    /// Space between a bubble and its status line underneath.
    static let statusSpacing: CGFloat = 4
    /// Fixed height of the status line, whether or not it has text.
    static let statusLineHeight: CGFloat = 16

    /// How long a command runs before the UI shows it as running. Quick
    /// commands go straight to their result without flashing a busy state.
    static let busyStateDelay: Duration = .milliseconds(300)

    // MARK: Bubbles

    static let bubbleHorizontalPadding: CGFloat = 12
    static let bubbleVerticalPadding: CGFloat = 7
    static let bubbleCornerRadius: CGFloat = 16
    /// Space kept free beside a bubble, so commands and replies read as two sides.
    static let bubbleOppositeInset: CGFloat = 64
    /// Larger surfaces in the transcript, such as the embedded terminal.
    static let cardCornerRadius: CGFloat = 16
    static let embeddedTerminalHeight: CGFloat = 440

    /// Height of a reply bubble holding a single line of monospaced text.
    static func singleLineBubbleHeight(fontSize: Double, monospaced: Bool = false) -> CGFloat {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont.systemFont(ofSize: fontSize)
        return ceil(font.ascender - font.descender + font.leading) + bubbleVerticalPadding * 2
    }

    // MARK: Composer

    /// Height of the message field and its circular buttons.
    static let composerControlSize: CGFloat = 36
    static let composerSpacing: CGFloat = 8
    static let composerVerticalPadding: CGFloat = 12
    static let composerFieldHorizontalPadding: CGFloat = 14

    // MARK: Sidebar

    static let avatarSize: CGFloat = 32
    static let sidebarRowSpacing: CGFloat = 10
    static let sidebarRowVerticalPadding: CGFloat = 6
}
