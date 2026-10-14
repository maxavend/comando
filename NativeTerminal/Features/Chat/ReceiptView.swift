import AppKit
import SwiftUI

/// Small status line under a reply, like “Delivered” in Messages.
struct ReceiptView: View {
    let entry: CommandEntry

    var body: some View {
        // The symbol shape (check vs. cross) carries the status, not only its color.
        HStack(spacing: 4) {
            if entry.wasInterrupted {
                Image(systemName: "stop.circle")
                Text("Interrumpido")
            } else if entry.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Completado")
            } else if let code = entry.exitCode {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Código \(code)")
            }
            if let duration = entry.duration, duration >= .milliseconds(50), !entry.wasInterrupted {
                Text(duration.chatFormatted)
            }
            if entry.truncated {
                Text("· Salida recortada")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .accessibilityElement(children: .combine)
    }
}
