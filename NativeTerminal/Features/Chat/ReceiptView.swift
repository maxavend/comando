import SwiftUI

/// Status under a finished reply, in plain words.
struct ReceiptView: View {
    let entry: CommandEntry

    var body: some View {
        // The symbol shape (check, cross, stop) carries the status, not only its color.
        StatusLine {
            if entry.wasInterrupted {
                Image(systemName: "stop.circle.fill")
                Text("Interrumpido")
            } else if entry.wasStopped {
                Image(systemName: "stop.circle.fill")
                Text("Detenido")
            } else if entry.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Listo")
            } else if let code = entry.exitCode {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Error · código \(code)")
            }
            if let duration = entry.duration, duration >= .milliseconds(50), !entry.wasInterrupted {
                Text("· \(duration.chatFormatted)")
            }
            if entry.truncated {
                Text("· Salida recortada")
            }
        }
    }
}
