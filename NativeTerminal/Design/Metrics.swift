import AppKit
import SwiftUI

/// Shared layout constants, so every screen lines up on the same grid.
nonisolated enum Metrics {
    // MARK: Chat

    /// Horizontal inset shared by the chat transcript and the composer.
    static let contentInset: CGFloat = 20
    /// Vertical inset at the top and bottom of the transcript.
    static let transcriptVerticalInset: CGFloat = 16
    /// Space between one exchange (command + reply) and the next, and between
    /// unrelated blocks elsewhere.
    static let exchangeSpacing: CGFloat = 16
    /// Space between chat bubbles when the side changes, as in Messages.
    static let messageSpacing: CGFloat = 8
    /// Space above a timestamp, which marks a pause in the conversation.
    static let timestampSpacing: CGFloat = 20
    /// Widest a bubble of words gets, as a share of the transcript.
    static let textBubbleFraction: CGFloat = 0.72
    /// Space between a command bubble and its reply.
    static let replySpacing: CGFloat = 8
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
    static let bubbleCornerRadius: CGFloat = 18
    /// Space kept free beside a bubble, so commands and replies read as two sides.
    static let bubbleOppositeInset: CGFloat = 64
    /// Space between the blocks of a rich reply (text, command, buttons).
    static let replyBlockSpacing: CGFloat = 10
    /// A command shown inside a reply, set in a recessed “well”.
    static let wellCornerRadius: CGFloat = 8
    static let wellHorizontalPadding: CGFloat = 10
    static let wellVerticalPadding: CGFloat = 6
    /// Space between small buttons and chips laid out in a row.
    static let chipSpacing: CGFloat = 6
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
    static let composerVerticalPadding: CGFloat = 8
    /// Space between the composer and the window's sides and bottom.
    static let composerEdgeInset: CGFloat = 10
    static let composerFieldHorizontalPadding: CGFloat = 14

    // MARK: Sidebar

    // As in the Messages sidebar (measured at 1:1): a 40-point avatar and the
    // unread dot in a gutter before it; the row is as tall as its text.
    static let avatarSize: CGFloat = 40
    static let sidebarRowSpacing: CGFloat = 10
    static let sidebarRowVerticalPadding: CGFloat = 6
    /// Room before the avatar for the unread dot.
    static let unreadGutter: CGFloat = 14
    static let unreadDotSize: CGFloat = 9
}
