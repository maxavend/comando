import SwiftUI

/// ⌘K: find a task by describing it, then run it or write it in the composer.
struct RecipesView: View {
    let directory: String
    let onRun: (String) -> Void
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @State private var chosen: Recipe?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if let chosen {
                RecipeDetailView(
                    recipe: chosen,
                    directory: directory,
                    onBack: { self.chosen = nil },
                    onRun: finish(running:),
                    onInsert: finish(inserting:)
                )
            } else {
                list
            }
        }
        .frame(width: 620, height: 520)
        #if DEBUG
        .onDebugAction("#query") { query = $0 }
        .onDebugAction("#choose") { _ in choose(at: selection, in: results) }
        .onDebugAction("#close") { _ in dismiss() }
        #endif
    }

    private var results: [Recipe] { RecipeBook.search(query) }

    private var list: some View {
        let results = results
        return VStack(spacing: 0) {
            HStack(spacing: Metrics.composerSpacing) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("¿Qué quieres hacer? Por ejemplo: comprimir, espacio, puerto", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit { choose(at: selection, in: results) }
                    .onKeyPress(.downArrow) { move(by: 1, count: results.count) }
                    .onKeyPress(.upArrow) { move(by: -1, count: results.count) }
                    .onChange(of: query) { selection = 0 }
            }
            .padding(Metrics.contentInset)

            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Recipe.Category.allCases, id: \.self) { category in
                                let items = results.enumerated().filter { $0.element.category == category }
                                if !items.isEmpty {
                                    Text(category.rawValue)
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, Metrics.bubbleHorizontalPadding)
                                        .padding(.top, Metrics.exchangeSpacing)
                                        .padding(.bottom, Metrics.statusSpacing)
                                    ForEach(items, id: \.element.id) { index, recipe in
                                        RecipeRow(recipe: recipe, isSelected: index == selection) {
                                            choose(at: index, in: results)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Metrics.contentInset - Metrics.bubbleHorizontalPadding)
                        .padding(.bottom, Metrics.transcriptVerticalInset)
                    }
                    .onChange(of: selection) { _, index in
                        if results.indices.contains(index) {
                            proxy.scrollTo(results[index].id, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("↩ elegir · ↑↓ moverte · esc cerrar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Metrics.contentInset)
            .padding(.vertical, Metrics.bubbleHorizontalPadding)
        }
        .onAppear { isSearchFocused = true }
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
        dismiss()
        onRun(command)
    }

    private func finish(inserting command: String) {
        dismiss()
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
                Image(systemName: recipe.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)
                    .background(.tint.quaternary, in: .rect(cornerRadius: 7))
                    .accessibilityHidden(true)
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
