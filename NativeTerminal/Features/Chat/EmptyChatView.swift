import SwiftUI

struct EmptyChatView: View {
    let directory: String

    var body: some View {
        ContentUnavailableView {
            Label("Sesión nueva", systemImage: "apple.terminal")
        } description: {
            Text("Escribe un comando abajo para empezar.\nEstás en \(ShellEscape.abbreviate(directory)).")
        }
    }
}
