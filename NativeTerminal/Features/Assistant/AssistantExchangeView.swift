import SwiftUI

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
                    Image(systemName: "apple.intelligence")
                    Text("Apple Intelligence · en este Mac")
                }
            }
        }
    }

    @ViewBuilder
    private var reply: some View {
        if !entry.isFinished {
            HStack(spacing: Metrics.composerSpacing) {
                ProgressView().controlSize(.small)
                Text("Buscando la mejor herramienta…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = entry.assistantError {
            Text(error)
                .fixedSize(horizontal: false, vertical: true)
        } else {
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
                actions
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
