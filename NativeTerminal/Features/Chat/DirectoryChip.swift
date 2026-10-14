import AppKit
import SwiftUI

struct DirectoryChip: View {
    let directory: String

    var body: some View {
        Label(ShellEscape.abbreviate(directory), systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Carpeta \(ShellEscape.abbreviate(directory))")
    }
}
