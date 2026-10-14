import AppKit
import SwiftUI

/// What a package is, how much space it takes and what to do with it.
struct PackageInspector: View {
    let package: ManagedPackage
    let isBusy: Bool
    let onRun: (String) -> Void
    let onUninstall: () -> Void

    @State private var size: Int64?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
                    Label {
                        Text(package.name)
                            .font(.title3.bold())
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: package.source.systemImage)
                            .foregroundStyle(.tint)
                    }
                    if !package.detail.isEmpty {
                        Text(package.detail)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, Metrics.statusSpacing)
            }

            if let latest = package.latest {
                Section {
                    LabeledContent {
                        Button("Actualizar") { onRun(package.upgradeCommand) }
                            .buttonStyle(.glassProminent)
                            .disabled(isBusy)
                            .help(package.upgradeCommand)
                    } label: {
                        Label("Versión \(latest) disponible", systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                LabeledContent("Versión", value: package.version)
                LabeledContent("Origen", value: package.origin)
                if let installedAt = package.installedAt {
                    LabeledContent("Instalada") {
                        Text(installedAt, format: .dateTime.day().month().year())
                    }
                }
                if package.location != nil {
                    LabeledContent("Tamaño") {
                        if let size {
                            Text(size, format: .byteCount(style: .file))
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                if !package.isOnRequest {
                    LabeledContent("Instalada por", value: package.source == .npm
                                   ? String(localized: "Node.js") : String(localized: "otra herramienta"))
                }
            }

            if !package.commands.isEmpty {
                Section("Comandos que agrega") {
                    Text(package.commands.joined(separator: "  "))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section {
                if let location = package.location, FileManager.default.fileExists(atPath: location) {
                    Button("Mostrar en Finder", systemImage: "folder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location)
                    }
                }
                if let homepage = package.homepage {
                    Link(destination: homepage) {
                        Label("Sitio web", systemImage: "safari")
                    }
                }
                Button("Desinstalar…", systemImage: "trash", role: .destructive, action: onUninstall)
                    .disabled(isBusy)
            }
            .buttonStyle(.link)
        }
        .formStyle(.grouped)
        .task(id: package.id) {
            guard let location = package.location else { return }
            size = await PackageStore.size(of: location)
        }
    }
}
