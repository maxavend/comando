import SwiftUI

/// The search field at the top of the sidebar, in a glass capsule like the
/// one in Messages (the system search field can't take the glass). ⌘F focuses
/// it, ↑ ↓ move through the results, ↩ opens one and Escape clears it.
struct SidebarSearchField: View {
    @Binding var text: String
    /// The highlighted result.
    @Binding var selection: Int
    /// Opens the highlighted result.
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Buscar", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand(perform: clear)
                .onSubmit(onSubmit)
                .onKeyPress(.downArrow) {
                    guard !text.isEmpty else { return .ignored }
                    selection += 1
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !text.isEmpty else { return .ignored }
                    selection = max(selection - 1, 0)
                    return .handled
                }
            if !text.isEmpty {
                Button("Borrar búsqueda", systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        // 34 points tall, like the search field in Messages.
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { isFocused = true }
        .background {
            Button("Buscar") { isFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func clear() {
        text = ""
        isFocused = false
    }
}
