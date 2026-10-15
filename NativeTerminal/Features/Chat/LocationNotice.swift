import SwiftUI

/// A centered system notice when a command moved to another folder, like the
/// notices Messages shows between bubbles.
struct LocationNotice: View {
    let folder: String

    var body: some View {
        Label {
            Text("Ahora estás en \(Text(FolderName.phrase(folder)).fontWeight(.medium))")
        } icon: {
            Image(systemName: "folder")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, Metrics.replySpacing)
        .help(ShellEscape.abbreviate(folder))
    }
}
