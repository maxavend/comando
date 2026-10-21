import SwiftUI

/// A centered system notice when a command moved to another folder, like the
/// notices Messages shows between bubbles.
struct LocationNotice: View {
    let folder: String

    var body: some View {
        FolderNotice(folder: folder, isChange: true)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.replySpacing)
    }
}
