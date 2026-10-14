import SwiftUI

/// Centered context above an exchange: when it happened and in which folder,
/// like the timestamps between conversations in Messages.
struct ExchangeHeader: View {
    let date: Date?
    let directory: String?

    var body: some View {
        VStack(spacing: 2) {
            if let date {
                Text(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
            }
            if let directory {
                Label(ShellEscape.abbreviate(directory), systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .accessibilityLabel("Carpeta \(ShellEscape.abbreviate(directory))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.bottom, Metrics.replySpacing)
    }
}
