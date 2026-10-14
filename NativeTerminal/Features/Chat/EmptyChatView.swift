import SwiftUI

/// The start of a session: where you are and a few things to try.
struct EmptyChatView: View {
    let directory: String
    let onRun: (String) -> Void
    let onPickFolder: () -> Void
    let onShowRecipes: () -> Void

    var body: some View {
        VStack(spacing: Metrics.exchangeSpacing) {
            SymbolBadge(systemImage: "apple.terminal", size: 72)

            VStack(spacing: Metrics.statusSpacing) {
                Text("¿Qué quieres hacer?")
                    .font(.title3.bold())
                Label {
                    Text("Estás en \(Text(FolderName.display(directory)).bold()). Escribe un comando abajo o prueba una de estas opciones.")
                } icon: {
                    Image(systemName: FolderName.systemImage(directory))
                }
                .labelStyle(.titleOnly)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Grid(horizontalSpacing: Metrics.composerSpacing, verticalSpacing: Metrics.composerSpacing) {
                GridRow {
                    SuggestionCard(title: "Ver qué hay en esta carpeta", systemImage: "list.bullet", command: "ls -G") {
                        onRun("ls -G")
                    }
                    SuggestionCard(title: "Ir a otra carpeta…", systemImage: "folder", command: "cd …", action: onPickFolder)
                }
                GridRow {
                    SuggestionCard(title: "Ver el espacio en disco", systemImage: "internaldrive", command: "df -h /") {
                        onRun("df -h /")
                    }
                    SuggestionCard(title: "Ver la versión de macOS", systemImage: "info.circle", command: "sw_vers") {
                        onRun("sw_vers")
                    }
                }
            }
            .frame(maxWidth: 480)

            Button("Ver más ideas en Recetas (⌘K)", systemImage: "wand.and.sparkles", action: onShowRecipes)
                .buttonStyle(.link)
                .foregroundStyle(.tint)
        }
        .padding(Metrics.contentInset)
    }
}
