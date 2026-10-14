import SwiftUI

/// Toolbar item for folders inside a Git repository: branch, pending changes
/// and the everyday actions.
struct GitMenu: View {
    let info: GitInfo
    let isBusy: Bool
    let onRun: (String) -> Void

    var body: some View {
        Menu {
            Section {
                Button("Ver los cambios", systemImage: "list.bullet") { onRun("git status") }
                Button("Ver las diferencias", systemImage: "plus.forwardslash.minus") { onRun("git diff") }
                Button("Ver el historial", systemImage: "clock.arrow.circlepath") { onRun("git log --oneline -15") }
            } header: {
                Text(summary)
            }
            Section {
                Button("Traer los últimos cambios", systemImage: "arrow.down.circle") { onRun("git pull") }
            }
        } label: {
            Label(title, systemImage: "arrow.triangle.branch")
                .labelStyle(.titleAndIcon)
        }
        .disabled(isBusy)
        .help("Rama \(info.branch) · \(summary)")
    }

    private var title: String {
        info.changes > 0 ? "\(info.branch) · \(info.changes)" : info.branch
    }

    private var summary: String {
        info.changes == 0
            ? String(localized: "Sin cambios pendientes")
            : String(localized: "^[\(info.changes) archivo con cambios](inflect: true)")
    }
}
