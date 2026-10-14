import SwiftUI
import UniformTypeIdentifiers

/// The options of a recipe, with the resulting command shown as you fill them in.
struct RecipeDetailView: View {
    let recipe: Recipe
    let directory: String
    let onBack: () -> Void
    let onRun: (String) -> Void
    let onInsert: (String) -> Void

    @State private var values: [String: String] = [:]
    @State private var pickingParameter: RecipeParameter?
    @FocusState private var focusedParameter: String?

    var body: some View {
        let command = recipe.command(with: values)
        let isComplete = recipe.isComplete(values)
        VStack(alignment: .leading, spacing: 0) {
            Button("Recetas", systemImage: "chevron.left", action: onBack)
                .buttonStyle(.borderless)
                .padding([.horizontal, .top], Metrics.contentInset)

            HStack(spacing: Metrics.bubbleHorizontalPadding) {
                SymbolBadge(systemImage: recipe.systemImage, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.title)
                        .font(.title2.bold())
                    Text(recipe.detail)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Metrics.contentInset)

            Form {
                ForEach(recipe.parameters) { parameter in
                    field(for: parameter)
                }
                Section("Se ejecutará") {
                    Text(command)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let description = CommandGlossary.describe(command) {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Spacer(minLength: 0)
            Divider()

            HStack {
                Spacer()
                Button("Escribir en el campo") { onInsert(command) }
                    .disabled(!isComplete)
                Button("Ejecutar") { onRun(command) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }
            .padding(.horizontal, Metrics.contentInset)
            .padding(.vertical, Metrics.bubbleHorizontalPadding)
        }
        .onAppear { focusedParameter = recipe.parameters.first?.id }
        .fileImporter(
            isPresented: Binding(get: { pickingParameter != nil }, set: { if !$0 { pickingParameter = nil } }),
            allowedContentTypes: pickingParameter?.kind == .folder ? [.folder] : [.item]
        ) { result in
            guard let parameter = pickingParameter, case .success(let url) = result else { return }
            values[parameter.id] = relativePath(url)
        }
    }

    @ViewBuilder
    private func field(for parameter: RecipeParameter) -> some View {
        switch parameter.kind {
        case .text, .number:
            TextField(parameter.label, text: binding(parameter.id), prompt: Text(parameter.placeholder))
                .focused($focusedParameter, equals: parameter.id)
        case .folder, .file:
            LabeledContent(parameter.label) {
                HStack {
                    TextField(parameter.label, text: binding(parameter.id), prompt: Text(parameter.placeholder))
                        .labelsHidden()
                        .focused($focusedParameter, equals: parameter.id)
                    Button("Elegir…") { pickingParameter = parameter }
                }
            }
        }
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { values[id] = $0 })
    }

    /// Paths inside the current folder are written relative to it, like people type them.
    private func relativePath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let base = directory.hasSuffix("/") ? directory : directory + "/"
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }
}
