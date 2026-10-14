import SwiftUI

/// Gives a session a name, an emoji and a color, so it's easy to spot.
struct SessionAppearanceEditor: View {
    let session: TerminalSession
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji: String?
    @State private var colorIndex = 0

    private static let emojis = [
        "🚀", "🎨", "🧪", "🛠️", "📦", "🌐", "🐍", "☕️",
        "⚛️", "🐳", "🔥", "⭐️", "📚", "🎵", "🧠", "💡",
        "🗂️", "🔒", "📱", "🖥️", "🧹", "📝", "🎮", "🌱",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.exchangeSpacing) {
            HStack(spacing: Metrics.bubbleHorizontalPadding) {
                SessionAvatar(isRunning: false, emoji: emoji, colorIndex: colorIndex)
                    .scaleEffect(1.5)
                    .frame(width: 48, height: 48)
                TextField("Nombre", text: $name, prompt: Text(FolderName.display(session.directory)))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: Metrics.composerSpacing) {
                Text("Emoji")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                    ForEach(Self.emojis, id: \.self) { item in
                        Button { emoji = item } label: {
                            Text(item)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .background(emoji == item ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item)
                    }
                }
                Button("Sin emoji") { emoji = nil }
                    .buttonStyle(.link)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: Metrics.composerSpacing) {
                Text("Color")
                    .font(.headline)
                HStack(spacing: Metrics.composerSpacing) {
                    ForEach(SessionColor.all.indices, id: \.self) { index in
                        Button { colorIndex = index } label: {
                            Circle()
                                .fill(SessionColor.all[index].gradient)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.primary.opacity(colorIndex == index ? 0.8 : 0), lineWidth: 2)
                                        .padding(-4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(SessionColor.names[index]))
                        .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                    }
                }
                .padding(.leading, 4)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Listo", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.contentInset)
        .frame(width: 400)
        .onAppear {
            name = session.customName ?? ""
            emoji = session.emoji
            colorIndex = session.colorIndex
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.customName = trimmed.isEmpty ? nil : trimmed
        session.emoji = emoji
        session.colorIndex = colorIndex
        onDone()
        dismiss()
    }
}
