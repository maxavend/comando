import SwiftUI

/// One place for everything installed with Homebrew, npm, pipx and uv: what
/// it is, where it came from, and whether it needs an update. Changes run in
/// the chat, so their output stays visible.
struct ToolsView: View {
    enum Pane: Hashable {
        case all, updates, discover
        case source(ManagedPackage.Source)
    }

    @Environment(TerminalController.self) private var controller
    @Environment(\.openWindow) private var openWindow
    @State private var store = PackageStore()
    @State private var section: Pane? = .all
    @State private var query = ""
    @State private var showsDependencies = false
    @State private var selection: ManagedPackage.ID?
    @State private var showsInspector = true
    @State private var pendingRemoval: ManagedPackage?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Buscar herramientas"))
        .navigationTitle("Herramientas")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .task(id: controller.installedToolsVersion) {
            await reload()
        }
        .confirmationDialog(
            pendingRemoval.map { String(localized: "¿Desinstalar \($0.name)?") } ?? "",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { package in
            Button("Desinstalar", role: .destructive) { run(package.uninstallCommand) }
        } message: { package in
            Text(removalMessage(for: package))
        }
        .frame(minWidth: 760, minHeight: 440)
        #if DEBUG
        .onDebugAction("#toolsection") { name in
            switch name {
            case "updates": section = .updates
            case "discover": section = .discover
            case "npm": section = .source(.npm)
            default: section = .all
            }
        }
        .onDebugAction("#toolselect") { name in
            selection = store.packages.first { $0.name == name }?.id
        }
        #endif
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $section) {
            Section("Instaladas") {
                Label("Todas", systemImage: "square.stack.3d.up")
                    .badge(visible(store.packages).count)
                    .tag(Pane.all)
                Label("Para actualizar", systemImage: "arrow.up.circle")
                    .badge(outdated.count)
                    .tag(Pane.updates)
                ForEach(sources, id: \.self) { source in
                    Label(source.title, systemImage: source.systemImage)
                        .badge(visible(store.packages.filter { $0.source == source }).count)
                        .tag(Pane.source(source))
                }
            }
            Section("Descubrir") {
                Label("Recomendadas", systemImage: "sparkle.magnifyingglass")
                    .tag(Pane.discover)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if section == .discover {
            DiscoverToolsView(query: query, isInstalled: isInstalled) { tool in
                run(tool.installCommand)
            }
        } else if !store.hasLoaded {
            ProgressView("Revisando lo que tienes instalado…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if let note = nodeNote {
                    NodeVersionsNote(text: note)
                    Divider()
                }
                table
            }
            .inspector(isPresented: $showsInspector) {
                Group {
                    if let package = selectedPackage {
                        PackageInspector(package: package, onRun: run) {
                            pendingRemoval = package
                        }
                        .id(package.id)
                    } else {
                        ContentUnavailableView("Elige una herramienta", systemImage: "shippingbox",
                                               description: Text("Verás qué es, cuánto pesa y cómo actualizarla."))
                    }
                }
                .inspectorColumnWidth(min: 240, ideal: 270, max: 380)
            }
        }
    }

    private var table: some View {
        let rows = rows
        return Table(rows, selection: $selection) {
            TableColumn("Nombre") { package in
                VStack(alignment: .leading, spacing: 1) {
                    Text(package.name)
                        .fontWeight(.medium)
                    if !package.detail.isEmpty {
                        Text(package.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .padding(.vertical, 2)
            }
            .width(min: 160, ideal: 240)
            TableColumn("Versión") { package in
                VersionLabel(package: package)
            }
            .width(min: 80, ideal: 110)
            TableColumn("Origen") { package in
                VStack(alignment: .leading, spacing: 1) {
                    Text(package.source == .cask ? ManagedPackage.Source.formula.title : package.source.title)
                    if let node = package.nodeVersion {
                        Text("Node \(node)")
                            .font(.caption)
                    } else if package.source == .cask {
                        Text("App")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .width(min: 90, ideal: 130)
            TableColumn("Instalada") { package in
                Text(package.installedAt.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: ManagedPackage.ID.self) { ids in
            if let package = store.packages.first(where: { ids.contains($0.id) }) {
                if package.isOutdated {
                    Button("Actualizar", systemImage: "arrow.up.circle") { run(package.upgradeCommand) }
                }
                Button("Copiar nombre", systemImage: "doc.on.doc") { Pasteboard.copy(package.name) }
                Divider()
                Button("Desinstalar…", systemImage: "trash", role: .destructive) { pendingRemoval = package }
            }
        } primaryAction: { _ in
            showsInspector = true
        }
        .overlay {
            if rows.isEmpty {
                if !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if section == .updates {
                    ContentUnavailableView("Todo al día", systemImage: "checkmark.circle",
                                           description: Text(store.isCheckingUpdates ? "Buscando actualizaciones de npm…" : "No hay actualizaciones pendientes."))
                } else {
                    ContentUnavailableView("Nada instalado aquí", systemImage: "shippingbox")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu("Filtrar", systemImage: "line.3.horizontal.decrease") {
                Toggle("Mostrar dependencias", isOn: $showsDependencies)
            }
            .help("Muestra también lo que se instaló como parte de otra herramienta o viene con Node")
        }
        ToolbarItem(placement: .primaryAction) {
            if !outdated.isEmpty {
                Button("Actualizar todo", systemImage: "arrow.up.circle") { run(upgradeAllCommand) }
                    .help(upgradeAllCommand)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if store.isLoading || store.isCheckingUpdates {
                ProgressView().controlSize(.small)
            } else {
                Button("Volver a revisar", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Detalles", systemImage: "sidebar.trailing") { showsInspector.toggle() }
                .disabled(section == .discover)
        }
    }

    // MARK: - Data

    private var sources: [ManagedPackage.Source] {
        ManagedPackage.Source.allCases.filter { source in store.packages.contains { $0.source == source } }
    }

    private func visible(_ packages: [ManagedPackage]) -> [ManagedPackage] {
        showsDependencies ? packages : packages.filter(\.isOnRequest)
    }

    private var outdated: [ManagedPackage] { visible(store.packages).filter(\.isOutdated) }

    private var rows: [ManagedPackage] {
        var packages: [ManagedPackage]
        switch section {
        case .updates: packages = outdated
        case .source(let source): packages = visible(store.packages.filter { $0.source == source })
        default: packages = visible(store.packages)
        }
        guard !query.isEmpty else { return packages }
        return packages.filter { package in
            ([package.name, package.detail] + package.commands).contains { $0.localizedStandardContains(query) }
        }
    }

    private var selectedPackage: ManagedPackage? {
        store.packages.first { $0.id == selection }
    }

    private var subtitle: String {
        guard store.hasLoaded else { return "" }
        let count = visible(store.packages).count
        let installed = count == 1 ? String(localized: "1 instalada") : String(localized: "\(count) instaladas")
        return outdated.isEmpty ? installed : installed + " · " + String(localized: "\(outdated.count) por actualizar")
    }

    /// Several Node versions each keep their own globals; say so where it matters.
    private var nodeNote: String? {
        guard store.nodeVersions.count > 1, section == .all || section == .source(.npm) else { return nil }
        let active = store.activeNodeVersion.map { String(localized: " La que usas ahora es la \($0).") } ?? ""
        return String(localized: "Tienes \(store.nodeVersions.count) versiones de Node y cada una guarda sus propios paquetes globales.") + active
    }

    private var upgradeAllCommand: String {
        var commands: [String] = []
        // Dependencies come along with `brew upgrade`.
        if outdated.contains(where: { $0.source == .formula || $0.source == .cask }) { commands.append("brew upgrade") }
        if outdated.contains(where: { $0.source == .npm && $0.isActiveNode }) { commands.append("npm update -g") }
        return commands.joined(separator: " && ")
    }


    private func isInstalled(_ tool: CatalogTool) -> Bool {
        store.packages.contains { ($0.source == .formula || $0.source == .cask) && $0.name == tool.id }
            || ExecutableIndex.shared.names(for: controller.selectedShell?.pathEntries ?? []).contains(tool.command)
    }

    private func removalMessage(for package: ManagedPackage) -> String {
        var message = String(localized: "Se ejecutará en el chat: \(package.uninstallCommand)")
        if !package.isOnRequest {
            message += "\n\n" + String(localized: "Se instaló como parte de otra herramienta, que podría dejar de funcionar.")
        }
        return message
    }

    private func reload() async {
        await store.reload(path: controller.selectedShell?.pathEntries ?? [])
    }

    /// Runs in the selected chat session and brings the chat forward.
    private func run(_ command: String) {
        guard !command.isEmpty else { return }
        controller.runPackageCommand(command)
        openWindow(id: "main")
    }
}

private struct VersionLabel: View {
    let package: ManagedPackage

    var body: some View {
        HStack(spacing: 4) {
            Text(package.version)
                .monospacedDigit()
                .truncationMode(.middle)
            if package.isOutdated {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Hay una versión nueva")
            }
        }
        .lineLimit(1)
        .help(package.latest.map { String(localized: "Hay una versión nueva: \($0)") } ?? "")
    }
}

private struct NodeVersionsNote: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.contentInset)
            .padding(.vertical, Metrics.bubbleHorizontalPadding)
    }
}
