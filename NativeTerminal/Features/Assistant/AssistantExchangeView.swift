import SwiftUI
import UniformTypeIdentifiers

/// A request in plain words and the assistant's proposal.
struct AssistantExchangeView: View {
    let entry: CommandEntry
    let shell: ShellSession?
    let onEdit: (String) -> Void

    @Environment(TerminalController.self) private var controller
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(spacing: Metrics.replySpacing) {
            VStack(alignment: .trailing, spacing: Metrics.statusSpacing) {
                if !entry.attachmentPaths.isEmpty {
                    HStack(spacing: Metrics.statusSpacing) {
                        ForEach(entry.attachmentPaths, id: \.self) { AttachmentChip(path: $0) }
                    }
                }
                Label {
                    Text(entry.command)
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .bubble(.command)
            }
            .padding(.leading, Metrics.bubbleOppositeInset)
            .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
                reply
                    .bubble(.reply)
                    .padding(.trailing, Metrics.bubbleOppositeInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusLine {
                    IntelligenceGlyph()
                    Text("Apple Intelligence · en este Mac")
                }
            }
        }
    }

    @ViewBuilder
    private var reply: some View {
        if !entry.isFinished {
            HStack(spacing: Metrics.composerSpacing) {
                IntelligenceGlyph(isActive: true)
                thinking
            }
        } else if let error = entry.assistantError {
            Text(error)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            answer
        }
    }

    private var thinking: some View {
        ThinkingText(states: [
            String(localized: "Leyendo tu pedido…"),
            String(localized: "Revisando lo que tienes instalado…"),
            String(localized: "Buscando la mejor herramienta…"),
            String(localized: "Armando el comando…"),
        ])
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: Metrics.bubbleHorizontalPadding) {
            if let explanation = entry.assistantExplanation {
                Text(explanation)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(entry.proposals, id: \.self) { proposal in
                ProposalBlock(proposal: proposal, fontSize: fontSize) { package in
                    controller.installPackage(package, for: entry)
                }
            }
            let extras = entry.assistantExtras
            if let request = extras.fileRequest {
                FileRequestView(request: request, directory: entry.directory) { url in
                    controller.provide(url, to: entry)
                }
            }
            if !entry.proposals.isEmpty {
                actions
            }
            ForEach(extras.suggestions, id: \.self) { suggestion in
                SuggestionRow(suggestion: suggestion, isBusy: shell?.isBusy ?? false) {
                    controller.installPackage(suggestion.package, for: entry)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Metrics.composerSpacing) {
            if entry.assistantRanAt != nil {
                Label("Ejecutado", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button("Ejecutar", systemImage: "play.fill", action: run)
                    .buttonStyle(.glassProminent)
                    .disabled(shell?.isBusy ?? false)
            }
            Button("Editar", systemImage: "pencil", action: edit)
                .buttonStyle(.glass)
        }
        .controlSize(.small)
    }

    private func run() {
        controller.runProposals(of: entry)
    }

    private func edit() {
        onEdit(entry.proposals.map(\.command).joined(separator: " && "))
    }
}

private struct ProposalBlock: View {
    let proposal: AssistantProposal
    let fontSize: Double
    let onInstall: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            Text(proposal.command)
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.composerSpacing)
                .padding(.vertical, Metrics.bubbleVerticalPadding - 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.opacity(0.7), in: .rect(cornerRadius: Metrics.bubbleCornerRadius / 2))
            HStack(spacing: Metrics.statusSpacing) {
                Image(systemName: "wrench.and.screwdriver")
                Text(proposal.tool)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let package = proposal.missingPackage {
                HStack(spacing: Metrics.statusSpacing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Necesitas instalar \(package).")
                    Button("Instalar con Homebrew") { onInstall(package) }
                        .buttonStyle(.link)
                        .foregroundStyle(.tint)
                        .pointerStyle(.link)
                }
                .font(.caption)
            }
        }
    }
}

/// “Which file?”: files of the right kind in the folder, or any file from disk.
private struct FileRequestView: View {
    let request: FileRequest
    let directory: String
    let onChoose: (URL) -> Void

    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            ForEach(request.choices.prefix(4), id: \.self) { path in
                Button {
                    onChoose(url(for: path))
                } label: {
                    Label((path as NSString).lastPathComponent, systemImage: symbol)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.glass)
            }
            Button("Elegir archivo…", systemImage: "folder") { isPicking = true }
                .buttonStyle(.glass)
        }
        .controlSize(.small)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: contentTypes) { result in
            if case .success(let url) = result { onChoose(url) }
        }
        .fileDialogDefaultDirectory(URL(filePath: directory, directoryHint: .isDirectory))
    }

    private func url(for path: String) -> URL {
        path.hasPrefix("/") ? URL(filePath: path) : URL(filePath: directory, directoryHint: .isDirectory).appending(path: path)
    }

    private var symbol: String {
        switch request.kind {
        case .audio: "waveform"
        case .video: "film"
        case .image: "photo"
        case .folder: "folder"
        default: "doc"
        }
    }

    private var contentTypes: [UTType] {
        switch request.kind {
        case .audio: [.audio]
        case .video: [.movie]
        case .image: [.image]
        default: [.item, .folder]
        }
    }
}

/// A tool worth installing for this kind of task.
private struct SuggestionRow: View {
    let suggestion: ToolSuggestion
    let isBusy: Bool
    let onInstall: () -> Void

    @State private var didInstall = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.composerSpacing) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("¿Necesitas más? Prueba \(suggestion.title)")
                Text(suggestion.detail)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.composerSpacing)
            if didInstall {
                Label("Instalando…", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button("Instalar") {
                    didInstall = true
                    onInstall()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isBusy)
                .help(suggestion.installCommand)
            }
        }
        .font(.callout)
        .padding(.top, Metrics.statusSpacing)
    }
}
