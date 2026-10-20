import SwiftData
import SwiftUI

/// ⌘K: find a task by describing it, then run it or write it in the composer.
/// Floats over the window like Spotlight: a glass search capsule with the
/// results in a glass panel under it. A click outside or Esc closes it.
struct RecipesView: View {
    let directory: String
    let onRun: (String) -> Void
    let onInsert: (String) -> Void
    /// Edits one of “Mis recetas” (in a sheet over the chat, once this closes).
    let onEdit: (SavedRecipe) -> Void
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedRecipe.order) private var saved: [SavedRecipe]
    @State private var query = ""
    @State private var selection = 0
    @State private var chosen: Recipe?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let results = results
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                searchField(results)
                Group {
                    if let chosen {
                        RecipeDetailView(
                            recipe: chosen,
                            directory: directory,
                            onBack: { self.chosen = nil },
                            onRun: finish(running:),
                            onInsert: finish(inserting:)
                        )
                        .frame(height: 440)
                    } else {
                        list(results)
                    }
                }
                // Nothing inside goes past the rounded corners.
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
                .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            }
        }
        .frame(width: 640)
        .onAppear { isSearchFocused = true }
        #if DEBUG
        .onDebugAction("#query") { query = $0 }
        .onDebugAction("#choose") { _ in choose(at: selection, in: results) }
        .onDebugAction("#close") { _ in onClose() }
        #endif
    }

    /// The search capsule, like Spotlight's.
    private func searchField(_ results: [Recipe]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Busca qué hacer: comprimir, espacio, puerto…", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isSearchFocused)
                .onSubmit { choose(at: selection, in: results) }
                .onKeyPress(.downArrow) { move(by: 1, count: results.count) }
                .onKeyPress(.upArrow) { move(by: -1, count: results.count) }
                .onChange(of: query) {
                    selection = 0
                    chosen = nil
                }
                // Esc steps back from a recipe's options, then closes.
                .onExitCommand {
                    if chosen != nil { chosen = nil } else { onClose() }
                }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .glassEffect(.regular, in: .capsule)
    }

    /// The user's own recipes first, then the built-in ones.
    private var results: [Recipe] { mine + RecipeBook.search(query) }

    private var mine: [Recipe] {
        saved.map { $0.recipe(in: directory) }.filter { $0.matches(query) }
    }

    /// “Mis recetas” by group, in the order the user left them.
    private func mineByGroup(_ results: [Recipe]) -> [(group: String, items: [(offset: Int, element: Recipe)])] {
        let items = results.enumerated().filter { $0.element.category == .mine }
        var groups: [String] = []
        for item in items {
            let group = savedRecipe(for: item.element)?.group ?? ""
            if !groups.contains(group) { groups.append(group) }
        }
        return groups.map { group in
            (group, items.filter { (savedRecipe(for: $0.element)?.group ?? "") == group })
        }
    }

    private func savedRecipe(for recipe: Recipe) -> SavedRecipe? {
        saved.first { "saved-\($0.id.uuidString)" == recipe.id }
    }

    private func list(_ results: [Recipe]) -> some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(height: 220)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if saved.isEmpty && query.isEmpty {
                                Label("Guarda tus propios comandos: clic derecho en uno del chat › Guardar como receta.",
                                      systemImage: "bookmark")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, Metrics.bubbleHorizontalPadding)
                                    .padding(.top, Metrics.exchangeSpacing)
                            }
                            ForEach(mineByGroup(results), id: \.group) { group, items in
                                sectionHeader(group.isEmpty ? Recipe.Category.mine.rawValue : group)
                                ForEach(items, id: \.element.id) { index, recipe in
                                    savedRow(recipe, index: index, in: results)
                                }
                            }
                            ForEach(Recipe.Category.builtIn, id: \.self) { category in
                                let items = results.enumerated().filter { $0.element.category == category }
                                if !items.isEmpty {
                                    sectionHeader(category.rawValue)
                                    ForEach(items, id: \.element.id) { index, recipe in
                                        RecipeRow(recipe: recipe, isSelected: index == selection) {
                                            choose(at: index, in: results)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    // Like Spotlight: no scroll bar on the glass, even with
                    // “Mostrar barras de desplazamiento: Siempre” (.hidden
                    // keeps that one); ↑ ↓ and the trackpad still scroll.
                    .scrollIndicators(.never)
                    .frame(height: 440)
                    .onChange(of: selection) { _, index in
                        if results.indices.contains(index) {
                            proxy.scrollTo(results[index].id, anchor: .center)
                        }
                    }
                }
            }

        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.top, Metrics.exchangeSpacing)
            .padding(.bottom, Metrics.statusSpacing)
    }

    /// One of “Mis recetas”: edited from its menu, reordered by dragging it
    /// onto another (which also moves it to that one's group).
    @ViewBuilder
    private func savedRow(_ recipe: Recipe, index: Int, in results: [Recipe]) -> some View {
        let item = savedRecipe(for: recipe)
        RecipeRow(recipe: recipe, isSelected: index == selection) {
            choose(at: index, in: results)
        }
        .contextMenu {
            if let item {
                Button("Editar…", systemImage: "pencil") {
                    onClose()
                    onEdit(item)
                }
                Button("Duplicar", systemImage: "plus.square.on.square") { duplicate(item) }
                Divider()
                Button("Eliminar", systemImage: "trash", role: .destructive) { delete(item) }
            }
        }
        .draggable(item?.id.uuidString ?? "")
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first, let target = item else { return false }
            return move(id, before: target)
        }
    }

    private func duplicate(_ recipe: SavedRecipe) {
        let copy = SavedRecipe(title: String(localized: "\(recipe.title) (copia)"), command: recipe.command,
                               directory: recipe.directory)
        copy.words = recipe.words
        copy.parameters = recipe.parameters
        copy.systemImage = recipe.systemImage
        copy.colorIndex = recipe.colorIndex
        copy.group = recipe.group
        copy.staysInFolder = recipe.staysInFolder
        modelContext.insert(copy)
        reorder(insert: copy, after: recipe)
    }

    private func delete(_ recipe: SavedRecipe) {
        modelContext.delete(recipe)
        try? modelContext.save()
    }

    private func move(_ id: String, before target: SavedRecipe) -> Bool {
        guard let moved = saved.first(where: { $0.id.uuidString == id }), moved !== target else { return false }
        var ordered = saved.filter { $0 !== moved }
        ordered.insert(moved, at: ordered.firstIndex { $0 === target } ?? ordered.endIndex)
        moved.group = target.group
        for (position, recipe) in ordered.enumerated() { recipe.order = position }
        try? modelContext.save()
        return true
    }

    private func reorder(insert new: SavedRecipe, after previous: SavedRecipe) {
        var ordered = saved.filter { $0 !== new }
        ordered.insert(new, at: (ordered.firstIndex { $0 === previous } ?? ordered.endIndex - 1) + 1)
        for (position, recipe) in ordered.enumerated() { recipe.order = position }
        try? modelContext.save()
    }

    private func move(by offset: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .ignored }
        selection = (selection + offset + count) % count
        return .handled
    }

    /// Recipes without options run right away (their command is visible in the
    /// row); the rest open a short form.
    private func choose(at index: Int, in results: [Recipe]) {
        guard results.indices.contains(index) else { return }
        let recipe = results[index]
        if recipe.parameters.isEmpty {
            finish(running: recipe.command(with: [:]))
        } else {
            chosen = recipe
        }
    }

    private func finish(running command: String) {
        onClose()
        onRun(command)
    }

    private func finish(inserting command: String) {
        onClose()
        onInsert(command)
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.bubbleHorizontalPadding) {
                if let tint = recipe.tint {
                    RecipeTile(systemImage: recipe.systemImage, colorIndex: tint)
                } else {
                    Image(systemName: recipe.systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)
                        .background(.tint.quaternary, in: .rect(cornerRadius: 7))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(recipe.title)
                    Text(recipe.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Metrics.composerSpacing)
                Text(recipe.command(with: [:]))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            .padding(.horizontal, Metrics.bubbleHorizontalPadding)
            .padding(.vertical, Metrics.bubbleVerticalPadding)
            .background(
                isSelected || isHovering ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
                in: .rect(cornerRadius: Metrics.bubbleCornerRadius / 2)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityHint(recipe.detail)
    }
}
