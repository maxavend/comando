import SwiftUI

/// Gives a session a name, a symbol or emoji, and a color, so it's easy to spot.
struct SessionAppearanceEditor: View {
    let session: TerminalSession
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji: String?
    @State private var symbol: String?
    @State private var colorIndex = 0

    /// Symbols for the kinds of work a terminal session is for.
    private static let symbols = [
        "apple.terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill", "wrench.and.screwdriver.fill",
        "server.rack", "externaldrive.fill", "antenna.radiowaves.left.and.right", "globe",
        "shippingbox.fill", "cube.fill", "gearshape.fill", "ladybug.fill",
        "doc.text.fill", "photo.fill", "film.fill", "music.note",
        "cloud.fill", "lock.fill", "key.fill", "cpu.fill",
        "iphone", "desktopcomputer", "book.fill", "briefcase.fill",
    ]

    private static let emojis = [
        "🚀", "🎨", "🧪", "🛠️", "📦", "🌐", "🐍", "☕️",
        "⚛️", "🐳", "🔥", "⭐️", "📚", "🎵", "🧠", "💡",
        "🗂️", "🔒", "📱", "🖥️", "🧹", "📝", "🎮", "🌱",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.exchangeSpacing) {
            HStack(spacing: Metrics.bubbleHorizontalPadding) {
                // Drawn at its size, not scaled up, so the symbol stays sharp.
                SessionAvatar(isRunning: false, emoji: emoji, colorIndex: colorIndex, size: 48,
                              symbol: symbol ?? SessionSymbol.symbol(for: session.directory))
                TextField("Nombre", text: $name, prompt: Text(FolderName.display(session.directory)))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: Metrics.composerSpacing) {
                Text("Símbolo")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                    // The first one fits the folder, and follows it if it changes.
                    symbolButton(nil, image: SessionSymbol.symbol(for: session.directory), label: "Automático")
                    ForEach(Self.symbols.filter { $0 != SessionSymbol.symbol(for: session.directory) }.prefix(23), id: \.self) { item in
                        symbolButton(item, image: item, label: LocalizedStringKey(item))
                    }
                }
            }

            VStack(alignment: .leading, spacing: Metrics.composerSpacing) {
                Text("Emoji")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8), spacing: 6) {
                    ForEach(Self.emojis, id: \.self) { item in
                        Button { emoji = item; symbol = nil } label: {
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
                    .pointerStyle(.link)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: Metrics.composerSpacing) {
                Text("Color")
                    .font(.headline)
                HStack(spacing: Metrics.composerSpacing) {
                    ForEach(SessionColor.all.indices, id: \.self) { index in
                        Button { colorIndex = index } label: {
                            Circle()
                                .fill(SessionColor.fill(at: index))
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
            symbol = session.symbolName
            colorIndex = session.colorIndex
        }
    }

    private func symbolButton(_ value: String?, image: String, label: LocalizedStringKey) -> some View {
        let selected = emoji == nil && symbol == value
        return Button {
            symbol = value
            emoji = nil
        } label: {
            Image(systemName: image)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 36, height: 36)
                .background(selected ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(value == nil ? Text("Automático: según la carpeta") : Text(image))
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.customName = trimmed.isEmpty ? nil : trimmed
        session.emoji = emoji
        session.symbolName = emoji == nil ? symbol : nil
        session.colorIndex = colorIndex
        onDone()
        dismiss()
    }
}
