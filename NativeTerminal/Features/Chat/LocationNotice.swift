import SwiftUI

/// A centered system notice when a command moved to another folder, like the
/// notices Messages shows between bubbles.
struct LocationNotice: View {
    let folder: String
    var session: TerminalSession?

    var body: some View {
        FolderNotice(folder: folder, session: session, isChange: true)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.replySpacing)
    }
}
