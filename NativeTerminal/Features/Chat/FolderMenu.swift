import AppKit
import SwiftUI

/// Toolbar menu to move between folders without typing `cd`.
struct FolderMenu: View {
    let session: TerminalSession
    let directory: String

    var body: some View {
        // Names the folder, so the leading side of the bar says where you are.
        Menu {
            FolderMenuItems(session: session, directory: directory)
        } label: {
            Label(FolderName.display(directory), systemImage: "folder")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .accessibilityLabel("Carpeta \(FolderName.display(directory))")
        .help("En \(FolderName.breadcrumb(directory)). Ir a otra carpeta")
    }
}

/// Where the session can go: up, the usual places, recent folders, any
/// folder, or the folder in Finder.
struct FolderMenuItems: View {
    let session: TerminalSession
    let directory: String

    @Environment(TerminalController.self) private var controller

    var body: some View {
        let isBusy = controller.shells[session.id]?.isBusy ?? false
        Section(FolderName.breadcrumb(directory)) {
            Button("Mostrar en Finder", systemImage: "macwindow") { showInFinder(directory) }
            Button("Subir un nivel", systemImage: "arrow.up", action: goUp)
                .disabled(isBusy || directory == "/")
        }
        Section("Lugares") {
            ForEach(FolderPlaces.standard, id: \.self) { place in
                FolderButton(folder: place) { go(to: place) }
                    .disabled(isBusy || place == directory)
            }
        }
        let recents = session.recentDirectories.filter { $0 != directory && !FolderPlaces.standard.contains($0) }
        if !recents.isEmpty {
            Section("Recientes") {
                ForEach(recents.prefix(5), id: \.self) { recent in
                    FolderButton(folder: recent) { go(to: recent) }
                        .disabled(isBusy)
                }
            }
        }
        Divider()
        Button("Ir a una carpeta…", systemImage: "folder.badge.questionmark", action: pickFolder)
            .disabled(isBusy)
    }

    private func goUp() { controller.navigateUp(in: session) }
    private func go(to folder: String) { controller.navigate(to: folder, in: session) }

    private func pickFolder() { controller.isPickingFolder = true }

    private func showInFinder(_ folder: String) {
        NSWorkspace.shared.open(URL(filePath: folder, directoryHint: .isDirectory))
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
