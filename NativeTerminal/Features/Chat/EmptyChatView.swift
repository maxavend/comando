import AppKit
import SwiftUI

struct EmptyChatView: View {
    let directory: String

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sesión nueva")
            } icon: {
                // The app icon, rendered by the system with its Liquid Glass layers.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
        } description: {
            Text("Escribe un comando abajo para empezar.\nEstás en \(ShellEscape.abbreviate(directory)).")
        }
    }
}
