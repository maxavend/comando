import SwiftUI

extension AgentKind {
    /// The agent's avatar: its initial in a circle, like a contact.
    nonisolated var symbol: String {
        switch self {
        case .agy: "a.circle.fill"
        case .claude: "asterisk.circle.fill"
        case .qwen: "q.circle.fill"
        case .codex: "c.circle.fill"
        }
    }
}

/// The start of a conversation with an agent: the command the user sent, and
/// a card saying who they're talking to, with what can be done.
struct AgentStartCard: View {
    let entry: CommandEntry

    @Environment(TerminalController.self) private var controller
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        let kind = entry.agentKind ?? .agy
        let isOpen = entry.finishedAt == nil
        VStack(spacing: Metrics.replySpacing) {
            Text(entry.command)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(.white)
                .bubble(.command)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(spacing: Metrics.statusSpacing) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
                Text(isOpen ? "Conversación con \(kind.displayName)" : "Terminó la conversación con \(kind.displayName)")
                    .font(.headline)
                Text(isOpen
                     ? "Sus respuestas llegan como mensajes. Escríbele abajo."
                     : "Puedes retomarla donde quedó.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if isOpen, let session = entry.session, let chat = controller.agentChats[session.id] {
                    AgentStatus(chat: chat, isInTerminal: controller.shells[session.id]?.isBusy ?? false)
                        .padding(.top, 2)
                }
                HStack(spacing: Metrics.chipSpacing) {
                    if isOpen {
                        Button("Ver en la terminal", systemImage: "macwindow") {
                            if let session = entry.session { controller.openAgentInTerminal(in: session) }
                        }
                        .help("Abre la misma conversación en la pantalla de \(kind.rawValue); después vuelves al chat")
                        Button("Terminar", systemImage: "xmark") {
                            if let session = entry.session { controller.finishActivity(in: session) }
                        }
                    } else if entry.agentConversationID != nil {
                        Button("Retomar", systemImage: "arrow.uturn.forward") { controller.resumeAgent(from: entry) }
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.regular)
                .buttonBorderShape(.capsule)
                .padding(.top, Metrics.statusSpacing)
            }
            .multilineTextAlignment(.center)
            .padding(Metrics.bubbleHorizontalPadding)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.statusSpacing)
            // While this card shows, the bar under the header isn't needed.
            .onScrollVisibilityChange(threshold: 0.4) { visible in
                if visible { controller.visibleActivityCards.insert(entry.id) } else { controller.visibleActivityCards.remove(entry.id) }
            }
            .onDisappear { controller.visibleActivityCards.remove(entry.id) }
        }
    }
}

/// Whether the agent is starting, ready, or couldn't start.
private struct AgentStatus: View {
    let chat: AgentChat
    let isInTerminal: Bool

    var body: some View {
        HStack(spacing: Metrics.statusSpacing) {
            if isInTerminal {
                Image(systemName: "macwindow")
                Text("Abierto en la terminal")
            } else if let error = chat.startupError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).lineLimit(2)
            } else if chat.isReady {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("En línea · ya puedes escribir")
            } else {
                ProgressView().controlSize(.mini)
                Text("Iniciando \(chat.kind.rawValue)…")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .animation(.smooth(duration: 0.25), value: chat.isReady)
        .accessibilityElement(children: .combine)
    }
}

/// A message to the agent and its answer: text in bubbles, and what it did
/// as cards in between.
struct AgentExchangeView: View {
    let entry: CommandEntry

    @Environment(TerminalController.self) private var controller
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        let kind = entry.agentKind ?? .agy
        let reply = entry.agentReply
        VStack(alignment: .leading, spacing: Metrics.replySpacing) {
            Text(entry.command)
                .font(.system(size: fontSize))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .bubble(.command)
                .bubbleWidth(Metrics.textBubbleFraction, alignment: .trailing)

            ForEach(reply.steps) { step in
                switch step.kind {
                case .text:
                    AgentText(text: step.text, fontSize: fontSize)
                        .bubble(.reply)
                        .bubbleWidth(0.86, alignment: .leading)
                case .tool:
                    AgentToolRow(step: step, fontSize: fontSize)
                        .bubbleWidth(0.86, alignment: .leading)
                }
            }

            if !entry.isFinished {
                HStack(spacing: Metrics.composerSpacing) {
                    IntelligenceSpinner(size: fontSize * 1.25)
                    ThinkingText(states: reply.steps.isEmpty
                                 ? [String(localized: "\(kind.rawValue) está pensando…")]
                                 : [String(localized: "\(kind.rawValue) está trabajando…")])
                }
                .font(.system(size: fontSize))
                .padding(.horizontal, Metrics.bubbleHorizontalPadding)
                .padding(.vertical, Metrics.bubbleVerticalPadding)
            }

            if entry.isFinished, !reply.denied.isEmpty {
                PermissionCard(kind: kind, denied: reply.denied, fontSize: fontSize) { permission in
                    if let session = entry.session { controller.allowAgent(permission, in: session) }
                }
                .bubbleWidth(0.86, alignment: .leading)
            }

            if let error = reply.error {
                AgentError(kind: kind, message: error, openedTerminal: reply.openedTerminal == true) {
                    if let session = entry.session { controller.openAgentInTerminal(in: session) }
                }
                .bubbleWidth(0.86, alignment: .leading)
            }
        }
    }
}

/// The agent's words, with its Markdown: bold, code and links.
private struct AgentText: View {
    let text: String
    let fontSize: Double

    var body: some View {
        Text(AgentTextFormat.markdown(text))
            .font(.system(size: fontSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The agent's Markdown, made to read like a message.
nonisolated enum AgentTextFormat {
    static func markdown(_ text: String) -> AttributedString {
        // Lists and headings read as they would in a message: bullets and
        // bold. Code blocks keep their lines, in code font.
        var inCode = false
        var lines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                continue
            }
            if inCode {
                lines.append(line.isEmpty ? "" : "`\(line.replacingOccurrences(of: "`", with: "'"))`")
            } else if let match = line.wholeMatch(of: /(\s*)[-*+] (.*)/) {
                lines.append("\(match.1)• \(match.2)")
            } else if let match = line.wholeMatch(of: /#{1,6} (.*)/) {
                lines.append("**\(match.1)**")
            } else {
                lines.append(String(line))
            }
        }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let prepared = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(text)
    }
}

/// One thing the agent did. Commands show what ran, and their output opens
/// below like a small terminal.
private struct AgentToolRow: View {
    let step: AgentReply.Step
    let fontSize: Double

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Metrics.statusSpacing) {
                    stateIcon
                        .frame(width: 16)
                    Image(systemName: step.symbol ?? "wrench.and.screwdriver")
                        .foregroundStyle(.secondary)
                    Text(step.state == .failed ? step.failedText ?? step.text : step.text)
                        .lineLimit(1)
                    if let detail = step.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: fontSize - 2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if hasOutput {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .font(.system(size: fontSize - 1))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!hasOutput)
            .padding(.horizontal, Metrics.bubbleHorizontalPadding)

            if isExpanded, let output = step.output {
                ScrollView {
                    Text(output)
                        .font(.system(size: fontSize - 2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.wellHorizontalPadding)
                .padding(.vertical, Metrics.wellVerticalPadding)
                .background(.fill.quinary, in: .rect(cornerRadius: Metrics.wellCornerRadius))
                .transition(.opacity)
            }
        }
    }

    private var hasOutput: Bool { !(step.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    @ViewBuilder
    private var stateIcon: some View {
        switch step.state {
        case .running:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.red)
        }
    }
}

/// The agent wanted to do something it isn't allowed to yet.
private struct PermissionCard: View {
    let kind: AgentKind
    let denied: [String]
    let fontSize: Double
    let onAllow: (AgentPermission) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.replyBlockSpacing) {
            Label {
                Text("\(kind.displayName) necesita permiso para \(denied.map(DeniedAction.describe).formatted(.list(type: .and))).")
            } icon: {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            }
            .font(.system(size: fontSize))
            .fixedSize(horizontal: false, vertical: true)
            if kind.hasPermissionModes {
                HStack(spacing: Metrics.chipSpacing) {
                    if denied.allSatisfy({ DeniedAction.describe($0) == DeniedAction.describe("write_file") }) {
                        Button("Permitir editar archivos", systemImage: "pencil") { onAllow(.edits) }
                            .buttonStyle(.glassProminent)
                    }
                    Button("Permitir todo en esta conversación", systemImage: "checkmark.shield") { onAllow(.all) }
                        .buttonStyle(.glass)
                }
                .controlSize(.regular)
                .buttonBorderShape(.capsule)
            } else {
                Text("Ábrelo en la terminal para darle permiso.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Metrics.bubbleHorizontalPadding - Metrics.bubbleVerticalPadding)
        .bubble(.reply)
    }
}

/// What went wrong, said simply, with the CLI's own words below and the
/// terminal one click away (to sign in, update, or check its settings).
private struct AgentError: View {
    let kind: AgentKind
    let message: String
    var openedTerminal = false
    let onOpenTerminal: () -> Void

    var body: some View {
        if message == String(localized: "Detenido") {
            Label("Detenido", systemImage: "stop.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Metrics.bubbleHorizontalPadding)
        } else {
            VStack(alignment: .leading, spacing: Metrics.statusSpacing) {
                Label {
                    Text(openedTerminal
                         ? "Abrí la terminal de \(kind.displayName) para continuar"
                         : "Para continuar, \(kind.displayName) necesita la terminal")
                        .font(.callout.weight(.semibold))
                } icon: {
                    Image(systemName: "macwindow.badge.plus").foregroundStyle(.tint)
                }
                Text(openedTerminal
                     ? "Hay algo que solo se puede hacer ahí, como iniciar sesión o confirmar. Cuando termines, vuelve al chat."
                     : "Ahí puedes iniciar sesión, actualizarlo o revisar su configuración. Después vuelve al chat.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                // The CLI's own message, for reference.
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !openedTerminal {
                    Button("Abrir en la terminal", systemImage: "macwindow", action: onOpenTerminal)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, Metrics.bubbleHorizontalPadding - Metrics.bubbleVerticalPadding)
            .bubble(.reply)
        }
    }
}
