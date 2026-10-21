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
                FolderNotice(folder: directory)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, date != nil ? Metrics.timestampSpacing - Metrics.messageSpacing : 0)
        .padding(.bottom, Metrics.statusSpacing)
    }
}

/// “Estás en tu carpeta personal”, or “Ahora estás en Escritorio” after a
/// `cd`: a record of where commands ran. Going somewhere else is the
/// toolbar's folder menu, so this is plain text.
struct FolderNotice: View {
    let folder: String
    /// The shell just moved here.
    var isChange = false

    var body: some View {
        let name = Text(FolderName.phrase(folder)).fontWeight(.medium)
        HStack(spacing: Metrics.statusSpacing) {
            Image(systemName: "folder")
            Text(isChange ? "Ahora estás en \(name)" : "Estás en \(name)")
        }
        .lineLimit(1)
        .help(ShellEscape.abbreviate(folder))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Carpeta \(FolderName.display(folder))")
    }
}
