import AppKit
import SwiftUI

/// Avatar colors people can give a session, from the system palette.
enum SessionColor {
    static let all: [Color] = [.gray, .blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal]

    static func color(at index: Int) -> Color {
        all.indices.contains(index) ? all[index] : .gray
    }

    /// The avatar's fill. The default is the gray of a contact without a
    /// photo in Messages: a soft gradient, lighter at the top.
    static func fill(at index: Int) -> AnyShapeStyle {
        guard index == 0 || !all.indices.contains(index) else { return AnyShapeStyle(color(at: index).gradient) }
        return AnyShapeStyle(LinearGradient(colors: [monogramTop, monogramBottom], startPoint: .top, endPoint: .bottom))
    }

    private static let monogramTop = Color(light: Color(red: 0.64, green: 0.65, blue: 0.70), dark: Color(red: 0.48, green: 0.47, blue: 0.54))
    private static let monogramBottom = Color(light: Color(red: 0.52, green: 0.53, blue: 0.58), dark: Color(red: 0.35, green: 0.31, blue: 0.45))

    static let names: [LocalizedStringKey] = [
        "Gris", "Azul", "Índigo", "Morado", "Rosa", "Rojo", "Naranja", "Amarillo", "Verde", "Turquesa",
    ]
}

extension Color {
    /// One color for light appearance and another for dark.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}
