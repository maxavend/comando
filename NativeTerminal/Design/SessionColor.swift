import SwiftUI

/// Avatar colors people can give a session, from the system palette.
enum SessionColor {
    static let all: [Color] = [.gray, .blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal]

    static func color(at index: Int) -> Color {
        all.indices.contains(index) ? all[index] : .gray
    }

    static let names: [LocalizedStringKey] = [
        "Gris", "Azul", "Índigo", "Morado", "Rosa", "Rojo", "Naranja", "Amarillo", "Verde", "Turquesa",
    ]
}
