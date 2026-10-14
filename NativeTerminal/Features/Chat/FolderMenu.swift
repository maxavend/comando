import AppKit
import SwiftUI

/// Toolbar menu to move between folders without typing `cd`.
struct FolderMenu: View {
    let session: TerminalSession
    let directory: String

    @Environment(TerminalController.self) private var controller

    var body: some View {
        let isBusy = controller.shells[session.id]?.isBusy ?? false
        Menu("Carpeta", systemImage: "folder") {
            Section(FolderName.breadcrumb(directory)) {
                Button("Subir un nivel", systemImage: "arrow.up", action: goUp)
                    .disabled(isBusy || directory == "/")
            }
            Section("Lugares") {
                ForEach(FolderPlaces.standard, id: \.self) { folder in
                    FolderButton(folder: folder) { go(to: folder) }
                        .disabled(isBusy || folder == directory)
                }
            }
            let recents = session.recentDirectories.filter { $0 != directory && !FolderPlaces.standard.contains($0) }
            if !recents.isEmpty {
                Section("Recientes") {
                    ForEach(recents.prefix(5), id: \.self) { folder in
                        FolderButton(folder: folder) { go(to: folder) }
                            .disabled(isBusy)
                    }
                }
            }
            Divider()
            Button("Ir a una carpeta…", systemImage: "folder.badge.questionmark", action: pickFolder)
                .disabled(isBusy)
            Button("Mostrar en Finder", systemImage: "macwindow", action: showInFinder)
        }
        .help("Ir a otra carpeta")
    }

    private func goUp() { controller.navigateUp(in: session) }
    private func go(to folder: String) { controller.navigate(to: folder, in: session) }
    private func pickFolder() { controller.isPickingFolder = true }

    private func showInFinder() {
        NSWorkspace.shared.open(URL(filePath: directory, directoryHint: .isDirectory))
    }
}

private struct FolderButton: View {
    let folder: String
    let action: () -> Void

    var body: some View {
        Button(FolderName.display(folder), systemImage: FolderName.systemImage(folder), action: action)
            .help(ShellEscape.abbreviate(folder))
    }
}

enum FolderPlaces {
    static var standard: [String] {
        let home = NSHomeDirectory()
        return [home, home + "/Desktop", home + "/Documents", home + "/Downloads"]
    }
}
