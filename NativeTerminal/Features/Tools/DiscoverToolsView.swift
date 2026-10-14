import SwiftUI

/// Well-known tools grouped by what they are for, installable in one click.
struct DiscoverToolsView: View {
    let query: String
    let isInstalled: (CatalogTool) -> Bool
    let isBusy: Bool
    let onInstall: (CatalogTool) -> Void

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: Metrics.bubbleHorizontalPadding)]

    var body: some View {
        let tools = filtered
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.exchangeSpacing) {
                ForEach(CatalogTool.Category.allCases, id: \.self) { category in
                    let items = tools.filter { $0.category == category }
                    if !items.isEmpty {
                        Text(category.rawValue)
                            .font(.headline)
                        LazyVGrid(columns: columns, spacing: Metrics.bubbleHorizontalPadding) {
                            ForEach(items) { tool in
                                ToolCard(tool: tool, isInstalled: isInstalled(tool), isBusy: isBusy) {
                                    onInstall(tool)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Metrics.contentInset)
        }
        .overlay {
            if tools.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private var filtered: [CatalogTool] {
        guard !query.isEmpty else { return ToolCatalog.all }
        return ToolCatalog.all.filter { tool in
            ([tool.title, tool.detail, tool.id] + tool.keywords).contains { $0.localizedStandardContains(query) }
        }
    }
}

private struct ToolCard: View {
    let tool: CatalogTool
    let isInstalled: Bool
    let isBusy: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.bubbleHorizontalPadding) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.quaternary, in: .rect(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .fontWeight(.medium)
                Text(tool.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tool.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("Ya la tienes")
                    .accessibilityLabel("Instalada")
            } else {
                Button("Instalar", action: onInstall)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(isBusy)
                    .help(tool.installCommand)
            }
        }
        .padding(Metrics.bubbleHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.fill.quinary, in: .rect(cornerRadius: Metrics.cardCornerRadius))
    }
}
