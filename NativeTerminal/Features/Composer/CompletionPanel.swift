import SwiftUI

/// Completion candidates in a glass panel above the composer field.
struct CompletionPanel: View {
    let candidates: [Completion]
    let selection: Int
    let onSelect: (Completion) -> Void

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(candidates.enumerated(), id: \.element.id) { index, candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    CompletionRow(candidate: candidate, fontSize: fontSize, isSelected: index == selection)
                }
                .buttonStyle(.plain)
            }
            Text("↩ para elegir · Tab o ↑↓ para moverte · esc para cerrar")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Metrics.bubbleHorizontalPadding)
                .padding(.top, Metrics.statusSpacing)
                .padding(.bottom, Metrics.statusSpacing / 2)
        }
        .padding(Metrics.statusSpacing + 2)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.composerControlSize / 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sugerencias")
    }
}

private struct CompletionRow: View {
    let candidate: Completion
    let fontSize: Double
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Metrics.composerSpacing) {
            Image(systemName: candidate.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(candidate.title)
                .font(.system(size: fontSize))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Metrics.composerSpacing)
            Text(candidate.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Metrics.bubbleHorizontalPadding - Metrics.statusSpacing - 2)
        .padding(.vertical, Metrics.bubbleVerticalPadding - 2)
        .background(
            isSelected ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear),
            in: .rect(cornerRadius: Metrics.bubbleCornerRadius / 2)
        )
        .contentShape(.rect)
    }
}
