import SwiftUI
import UniformTypeIdentifiers

/// A request in plain words and the assistant's answer.
struct AssistantExchangeView: View {
    let entry: CommandEntry
    let shell: ShellSession?
    let onEdit: (String) -> Void

    @Environment(TerminalController.self) private var controller
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        VStack(spacing: Metrics.replySpacing) {
            request
            if entry.isFinished {
                answer
                    // Replies with commands or buttons read as a card: the same
                    // inset on all four sides, and room for the command.
                    .padding(.vertical, isRich ? Metrics.bubbleHorizontalPadding - Metrics.bubbleVerticalPadding : 0)
                    .bubble(.reply)
                    .bubbleWidth(isRich ? 0.86 : Metrics.textBubbleFraction, alignment: .leading)
                    .transition(.opacity)
            } else {
                // Thinking isn't a message yet: no bubble, just the status,
                // lined up with the text of the bubble that will replace it.
                thinking
                    .padding(.horizontal, Metrics.bubbleHorizontalPadding)
                    .padding(.vertical, Metrics.bubbleVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: entry.isFinished)
    }

    private var isRich: Bool {
        let extras = entry.assistantExtras
        return entry.isFinished && (!entry.proposals.isEmpty || extras.template != nil || extras.fileRequest != nil
            || !extras.examples.isEmpty || !extras.suggestions.isEmpty)
    }

    private var request: some View {
        VStack(alignment: .trailing, spacing: Metrics.statusSpacing) {
            if !entry.attachmentPaths.isEmpty {
                HStack(spacing: Metrics.statusSpacing) {
                    ForEach(entry.attachmentPaths, id: \.self) { AttachmentChip(path: $0) }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: fontSize * 0.82, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(entry.command)
                    .textSelection(.enabled)
            }
            .font(.system(size: fontSize))
            .foregroundStyle(.white)
            .bubble(.request)
        }
        .bubbleWidth(Metrics.textBubbleFraction, alignment: .trailing)
    }

    private var thinking: some View {
        HStack(spacing: Metrics.composerSpacing) {
            IntelligenceGlyph(isActive: true)
            ThinkingText(states: [
                String(localized: "Leyendo tu pedido…"),
                String(localized: "Revisando lo que tienes instalado…"),
                String(localized: "Buscando la mejor herramienta…"),
                String(localized: "Armando el comando…"),
            ])
        }
        .font(.system(size: fontSize))
    }

    private var answer: some View {
        let extras = entry.assistantExtras
        let isBusy = shell?.isBusy ?? false
        return VStack(alignment: .leading, spacing: Metrics.replyBlockSpacing) {
            if let text = entry.assistantError ?? entry.assistantExplanation, !text.isEmpty {
                Text(text)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(entry.proposals, id: \.self) { proposal in
                ProposalBlock(proposal: proposal, fontSize: fontSize, isBusy: isBusy) { package in
                    if let install = proposal.install {
                        controller.runInstall(install, for: entry)
                    } else {
                        controller.installPackage(package, for: entry)
                    }
                }
            }
            if let template = extras.template {
                CommandWell(command: template, fontSize: fontSize)
            }
            if let request = extras.fileRequest {
                FileRequestView(request: request, directory: entry.directory) { url in
                    controller.provide(url, to: entry)
                }
            }
            if !entry.proposals.isEmpty || extras.template != nil {
                actions(template: extras.template, isBusy: isBusy)
            }
            if !extras.examples.isEmpty {
                ExampleChips(examples: extras.examples) { example in
                    guard let session = entry.session else { return }
                    controller.ask(example, attachments: [], in: session)
                }
            }
            ForEach(extras.suggestions, id: \.self) { suggestion in
                SuggestionRow(suggestion: suggestion, isBusy: isBusy) {
                    controller.runInstall(suggestion.installCommand, for: entry)
                }
            }
        }
    }

    private func actions(template: String?, isBusy: Bool) -> some View {
        HStack(spacing: Metrics.chipSpacing) {
            if template == nil {
                if entry.assistantRanAt != nil {
                    Label("Ejecutado", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Ejecutar", systemImage: "play.fill") { controller.runProposals(of: entry) }
                        .buttonStyle(.glassProminent)
                        .disabled(isBusy)
                }
            }
            Button(template == nil ? "Editar" : "Escribirlo", systemImage: "pencil") {
                onEdit(template ?? entry.proposals.map(\.command).joined(separator: " && "))
            }
            .buttonStyle(template == nil ? AnyPrimitiveButtonStyle(.glass) : AnyPrimitiveButtonStyle(.glassProminent))
        }
        // Regular-size capsules: easy to hit, and the same shape as the bubbles.
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
    }
}

/// A command set in a recessed well, so it reads as something to run.
private struct CommandWell: View {
    let command: String
    let fontSize: Double

    var body: some View {
        Text(command)
            .font(.system(size: fontSize, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Metrics.wellHorizontalPadding)
            .padding(.vertical, Metrics.wellVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.7), in: .rect(cornerRadius: Metrics.wellCornerRadius))
    }
}

private struct ProposalBlock: View {
    let proposal: AssistantProposal
    let fontSize: Double
    let isBusy: Bool
    let onInstall: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            CommandWell(command: proposal.command, fontSize: fontSize)
            Group {
                if let about = proposal.about {
                    // What the tool does, so the command isn't a mystery.
                    Caption(systemImage: "wrench.and.screwdriver", text: "\(proposal.tool) — \(about)")
                } else if proposal.isGenerated != true {
                    Caption(systemImage: "wrench.and.screwdriver", text: proposal.tool)
                }
                if proposal.isGenerated == true {
                    Caption(systemImage: "apple.intelligence",
                            text: String(localized: "Sugerido por Apple Intelligence · revísalo antes de ejecutar"))
                }
            }
            .padding(.leading, Metrics.wellHorizontalPadding)
            if let package = proposal.missingPackage {
                HStack(spacing: Metrics.statusSpacing) {
                    Caption(systemImage: "exclamationmark.triangle.fill", text: String(localized: "Necesitas instalar \(package)."), tint: .orange)
                    if package == "Homebrew" {
                        // Homebrew can't install itself: point to its site.
                        Link("Cómo instalarlo", destination: URL(string: "https://brew.sh/es/")!)
                            .font(.caption)
                            .pointerStyle(.link)
                    } else {
                        Button("Instalar") { onInstall(package) }
                            .buttonStyle(.link)
                            .font(.caption)
                            .pointerStyle(.link)
                            .disabled(isBusy)
                    }
                }
                .padding(.leading, Metrics.wellHorizontalPadding)
            }
        }
    }
}

/// A small line of secondary text with a leading symbol.
private struct Caption: View {
    let systemImage: String
    let text: String
    var tint: Color?

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        }
        .labelStyle(CaptionLabelStyle())
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Icon and text with the tight spacing of a caption.
private struct CaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.statusSpacing) {
            configuration.icon
            configuration.title
        }
    }
}

/// Requests to try, one click each.
private struct ExampleChips: View {
    let examples: [String]
    let onAsk: (String) -> Void

    var body: some View {
        FlowLayout(spacing: Metrics.chipSpacing) {
            ForEach(examples, id: \.self) { example in
                Button(example) { onAsk(example) }
                    .buttonStyle(.glass)
            }
        }
        // Regular-size capsules: easy to hit, and the same shape as the bubbles.
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
    }
}

/// “Which file?”: files of the right kind in the folder, or any file from disk.
private struct FileRequestView: View {
    let request: FileRequest
    let directory: String
    let onChoose: (URL) -> Void

    @State private var isPicking = false

    var body: some View {
        FlowLayout(spacing: Metrics.chipSpacing) {
            ForEach(request.choices.prefix(4), id: \.self) { path in
                Button {
                    onChoose(url(for: path))
                } label: {
                    Label((path as NSString).lastPathComponent, systemImage: AttachmentChip.symbol(for: request.kind))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.glass)
            }
            Button("Elegir archivo…", systemImage: "folder") { isPicking = true }
                .buttonStyle(.glass)
        }
        // Regular-size capsules: easy to hit, and the same shape as the bubbles.
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
        .fileImporter(isPresented: $isPicking, allowedContentTypes: contentTypes) { result in
            if case .success(let url) = result { onChoose(url) }
        }
        .fileDialogDefaultDirectory(URL(filePath: directory, directoryHint: .isDirectory))
    }

    private func url(for path: String) -> URL {
        path.hasPrefix("/") ? URL(filePath: path) : URL(filePath: directory, directoryHint: .isDirectory).appending(path: path)
    }

    private var contentTypes: [UTType] {
        switch request.kind {
        case .audio: [.audio]
        case .video: [.movie]
        case .image: [.image]
        case .pdf: [.pdf]
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
        VStack(alignment: .leading, spacing: Metrics.replyBlockSpacing) {
            Divider()
            HStack(alignment: .center, spacing: Metrics.composerSpacing) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    if let origin = suggestion.origin {
                        Text("También sirve \(Text(suggestion.title).bold()) · \(Text(origin).foregroundStyle(.secondary))")
                    } else {
                        Text("¿Necesitas más? Prueba \(suggestion.title)")
                    }
                    Text(suggestion.detail)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.composerSpacing)
                if suggestion.isInstalled {
                    Label("Instalada", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .help("Ya la tienes")
                } else if didInstall {
                    Label("Instalando…", systemImage: "arrow.down.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Instalar") {
                        didInstall = true
                        onInstall()
                    }
                    .buttonStyle(.glass)
                    // Regular-size capsules: easy to hit, and the same shape as the bubbles.
        .controlSize(.regular)
        .buttonBorderShape(.capsule)
                    .disabled(isBusy)
                    .help(suggestion.installCommand)
                }
            }
        }
    }
}

/// Lets two button styles be chosen at run time.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some PrimitiveButtonStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
