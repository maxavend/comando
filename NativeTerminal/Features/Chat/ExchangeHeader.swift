import SwiftUI

/// Centered context above an exchange, like the notes between conversations
/// in Messages: when it happened, after a pause, and which folder the shell is
/// in, when that changed.
struct ExchangeHeader: View {
    let date: Date?
    let directory: String?

    var body: some View {
        VStack(spacing: Metrics.statusSpacing) {
            if let date {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .fontWeight(.medium)
            }
            if let directory {
                Label {
                    Text("Estás en \(Text(FolderName.phrase(directory)).fontWeight(.medium))")
                } icon: {
                    Image(systemName: "folder")
                }
                .lineLimit(1)
                .help(ShellEscape.abbreviate(directory))
                .accessibilityLabel("Carpeta \(FolderName.display(directory))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, date != nil ? Metrics.timestampSpacing - Metrics.messageSpacing : 0)
        .padding(.bottom, Metrics.statusSpacing)
    }
}
