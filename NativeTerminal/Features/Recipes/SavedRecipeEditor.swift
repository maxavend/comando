import SwiftData
import SwiftUI

/// Saves a command as one of “Mis recetas”, or edits one: its name, symbol and
/// color, the words that are asked for each time, its group and its folder.
struct SavedRecipeEditor: View {
    /// The recipe being edited; nil saves a new one from `command`.
    let recipe: SavedRecipe?
    let command: String
    /// The folder the command ran in, offered as “Siempre en …”.
    let directory: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRecipe.order) private var saved: [SavedRecipe]

    @State private var title = ""
    @State private var systemImage = "terminal"
    @State private var colorIndex = 6
    @State private var asked: [Int: String] = [:]
    @State private var group = ""
    @State private var isNewGroup = false
    @State private var newGroup = ""
    @State private var runsInFolder = false
    @State private var isPickingSymbol = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, newGroup, label(Int) }

    private var words: [String] { recipe?.words ?? SavedRecipe.rawWords(command) }

    init(command: String, directory: String) {
        self.recipe = nil
        self.command = command
        self.directory = directory
    }

    init(editing recipe: SavedRecipe) {
        self.recipe = recipe
        self.command = recipe.command
        self.directory = recipe.directory
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 12) {
                        symbolButton
                        TextField("Nombre", text: $title, prompt: Text("Por ejemplo: Levantar la tienda"))
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .focused($focusedField, equals: .title)
                            .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            WordToken(word: word, label: asked[index], isAsked: asked[index] != nil) {
                                toggle(index)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    ForEach(asked.keys.sorted(), id: \.self) { index in
                        TextField(text: label(for: index), prompt: Text(placeholderLabel(for: index))) {
                            Text("«\(defaultValue(at: index))» se pregunta como")
                        }
                        .focused($focusedField, equals: .label(index))
                    }
                } header: {
                    Text("Comando")
                } footer: {
                    Text(asked.isEmpty
                         ? "Haz clic en una parte para que se pregunte cada vez que la uses."
                         : "Al usarla te pregunta cada dato, con lo que escribiste ya puesto.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    groupPicker
                    if isNewGroup {
                        TextField("Nombre del grupo", text: $newGroup, prompt: Text("Trabajo"))
                            .focused($focusedField, equals: .newGroup)
                    }
                    Picker("Dónde corre", selection: $runsInFolder) {
                        Text("En la carpeta donde estés").tag(false)
                        Text("Siempre en \(FolderName.display(directory))").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Se ejecutará") {
                    Text(preview)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if recipe != nil {
                    Button("Eliminar receta", role: .destructive, action: delete)
                }
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(recipe == nil ? "Guardar receta" : "Guardar", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
        #if DEBUG
        .onDebugAction("#recipeword") { argument in
            if let index = Int(argument) { toggle(index) }
        }
        .onDebugAction("#recipetitle") { title = $0 }
        .onDebugAction("#recipesave") { _ in save() }
        #endif
    }

    // MARK: - Parts

    private var symbolButton: some View {
        Button { isPickingSymbol = true } label: {
            RecipeTile(systemImage: systemImage, colorIndex: colorIndex, size: 44)
        }
        .buttonStyle(.plain)
        .help("Cambiar el símbolo y el color")
        .accessibilityLabel("Símbolo y color")
        .popover(isPresented: $isPickingSymbol, arrowEdge: .bottom) {
            RecipeSymbolPicker(systemImage: $systemImage, colorIndex: $colorIndex)
        }
    }

    private var groups: [String] {
        var seen = Set<String>()
        return saved.map(\.group).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var groupPicker: some View {
        Picker("Grupo", selection: Binding(
            get: { isNewGroup ? "\u{0}new" : group },
            set: { value in
                if value == "\u{0}new" {
                    isNewGroup = true
                    focusedField = .newGroup
                } else {
                    isNewGroup = false
                    group = value
                }
            }
        )) {
            Text("Sin grupo").tag("")
            if !groups.isEmpty {
                Divider()
                ForEach(groups, id: \.self) { Text($0).tag($0) }
            }
            Divider()
            Text("Nuevo grupo…").tag("\u{0}new")
        }
    }

    // MARK: - Asked-for words

    private func toggle(_ index: Int) {
        if asked[index] == nil {
            asked[index] = ""
            focusedField = .label(index)
        } else {
            asked[index] = nil
        }
    }

    private func label(for index: Int) -> Binding<String> {
        Binding(get: { asked[index] ?? "" }, set: { asked[index] = $0 })
    }

    private func defaultValue(at index: Int) -> String {
        SavedRecipeParameter(wordIndex: index, label: "").defaultValue(in: words)
    }

    /// A question for the word, guessed from the option before it
    /// (`--port 4321` → “Port”), or a plain “Valor”.
    private func placeholderLabel(for index: Int) -> String {
        if index > 0, words[index - 1].hasPrefix("--") {
            let option = words[index - 1].dropFirst(2)
            if option.count > 1 { return option.prefix(1).uppercased() + option.dropFirst() }
        }
        return String(localized: "Valor")
    }

    private var parameters: [SavedRecipeParameter] {
        asked.keys.sorted().map { index in
            let label = asked[index]?.trimmingCharacters(in: .whitespaces) ?? ""
            return SavedRecipeParameter(wordIndex: index, label: label.isEmpty ? placeholderLabel(for: index) : label)
        }
    }

    private var preview: String {
        let line = SavedRecipeCommand(words: words, parameters: parameters).command(with: [:])
        return runsInFolder ? "cd \(ShellEscape.abbreviate(directory)) && \(line)" : line
    }

    // MARK: - Saving

    private func load() {
        if let recipe {
            title = recipe.title
            systemImage = recipe.systemImage
            colorIndex = recipe.colorIndex
            group = recipe.group
            runsInFolder = recipe.staysInFolder
            asked = Dictionary(uniqueKeysWithValues: recipe.parameters.map { ($0.wordIndex, $0.label) })
        } else {
            systemImage = RecipeSymbolPicker.suggestedSymbol(for: command)
            focusedField = .title
        }
    }

    private func save() {
        let target = recipe ?? {
            let new = SavedRecipe(title: "", command: command, directory: directory)
            new.order = (saved.map(\.order).max() ?? -1) + 1
            modelContext.insert(new)
            return new
        }()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.title = trimmed.isEmpty ? command : trimmed
        target.systemImage = systemImage
        target.colorIndex = colorIndex
        target.parameters = parameters
        let groupName = isNewGroup ? newGroup.trimmingCharacters(in: .whitespacesAndNewlines) : group
        target.group = groupName
        target.staysInFolder = runsInFolder
        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        if let recipe { modelContext.delete(recipe) }
        try? modelContext.save()
        dismiss()
    }
}

/// One word of the command: plain, or highlighted as a value that's asked for.
private struct WordToken: View {
    let word: String
    let label: String?
    let isAsked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(word)
                .font(.body.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(isAsked ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isAsked ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary),
                            in: .rect(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(isAsked ? "No preguntar esta parte" : "Preguntar esta parte cada vez")
        .accessibilityLabel(word)
        .accessibilityAddTraits(isAsked ? .isSelected : [])
        .accessibilityHint(isAsked ? "Se pregunta al usar la receta" : "Haz clic para que se pregunte")
    }
}

/// A saved recipe's symbol on its color, like an app's tile.
struct RecipeTile: View {
    let systemImage: String
    let colorIndex: Int
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(SessionColor.color(at: colorIndex).gradient,
                        in: .rect(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Symbol and color for a saved recipe.
struct RecipeSymbolPicker: View {
    @Binding var systemImage: String
    @Binding var colorIndex: Int

    static let symbols = [
        "terminal", "play.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "arrow.triangle.branch", "shippingbox.fill", "server.rack", "globe",
        "folder.fill", "doc.text.fill", "photo.fill", "film.fill",
        "music.note", "archivebox.fill", "trash.fill", "magnifyingglass",
        "network", "cpu", "bolt.fill", "paperplane.fill",
        "flame.fill", "leaf.fill", "lock.fill", "ladybug.fill",
    ]

    /// A symbol that fits the program the command runs.
    static func suggestedSymbol(for command: String) -> String {
        let program = ShellEscape.words(command).first { !$0.contains("=") && $0 != "sudo" } ?? ""
        switch program {
        case "git", "gh": return "arrow.triangle.branch"
        case "npm", "npx", "yarn", "pnpm", "bun", "brew", "pip", "pip3", "docker": return "shippingbox.fill"
        case "ffmpeg", "yt-dlp": return "film.fill"
        case "cd", "ls", "open", "mkdir", "find": return "folder.fill"
        case "rm", "trash": return "trash.fill"
        case "zip", "unzip", "tar": return "archivebox.fill"
        case "ssh", "curl", "ping", "scp": return "network"
        case "make", "swift", "xcodebuild", "cargo", "go": return "hammer.fill"
        default: return "terminal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 6), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button { systemImage = symbol } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(systemImage == symbol ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .frame(width: 32, height: 32)
                            .background(systemImage == symbol ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.clear),
                                        in: .rect(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(systemImage == symbol ? .isSelected : [])
                }
            }
            Divider()
            HStack(spacing: 8) {
                ForEach(SessionColor.all.indices, id: \.self) { index in
                    Button { colorIndex = index } label: {
                        Circle()
                            .fill(SessionColor.color(at: index).gradient)
                            .frame(width: 20, height: 20)
                            .overlay {
                                Circle()
                                    .strokeBorder(.primary.opacity(colorIndex == index ? 0.8 : 0), lineWidth: 2)
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(SessionColor.names[index]))
                    .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                }
            }
            .padding(.leading, 3)
        }
        .padding(14)
    }
}
