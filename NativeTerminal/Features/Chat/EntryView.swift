import AppKit
import SwiftUI

/// One exchange in the chat: the command bubble and the shell's reply.
struct EntryView: View {
    let entry: CommandEntry
    let previous: CommandEntry?
    let shell: ShellSession?
    let isHighlighted: Bool
    let onEdit: (String) -> Void

    @Environment(TerminalController.self) private var controller

    var body: some View {
        let live = shell?.live
        VStack(spacing: 6) {
            if showsTimestamp {
                TimestampSeparator(date: entry.startedAt)
            }
            if showsDirectory {
                DirectoryChip(directory: entry.directory)
            }
            CommandBubble(command: entry.command)
                .contextMenu { commandMenu }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 80)

            if let shell, let live, live.entryID == entry.id {
                LiveResponseView(live: live, shell: shell)
            } else {
                FinishedResponseView(entry: entry, onRerun: { controller.rerun(entry) })
            }
        }
        .padding(.top, 10)
        .padding(.vertical, isHighlighted ? 4 : 0)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.quaternary)
                    .padding(.horizontal, -8)
            }
        }
    }

    @ViewBuilder
    private var commandMenu: some View {
        Button("Copiar comando", systemImage: "doc.on.doc") {
            Pasteboard.copy(entry.command)
        }
        Button("Editar y volver a enviar", systemImage: "pencil") {
            onEdit(entry.command)
        }
        Button("Volver a ejecutar", systemImage: "arrow.clockwise") {
            controller.rerun(entry)
        }
        .disabled(shell?.isBusy ?? false)
    }

    /// Like Messages: a timestamp when there's a pause of more than 15 minutes.
    private var showsTimestamp: Bool {
        guard let previous else { return true }
        return entry.startedAt.timeIntervalSince(previous.startedAt) > 15 * 60
    }

    private var showsDirectory: Bool {
        guard let previous else { return true }
        return previous.directory != entry.directory
    }
}

// MARK: - Bubbles

enum BubbleMetrics {
    static let horizontalPadding: CGFloat = 12
    /// Space kept free on the trailing side of replies, like received messages.
    static let trailingInset: CGFloat = 48
    static let cornerRadius: CGFloat = 17
}

struct CommandBubble: View {
    let command: String
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize

    var body: some View {
        Text(command)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.tint, in: .rect(cornerRadius: 17))
            .accessibilityLabel("Comando: \(command)")
    }
}

struct OutputBubble<Accessory: View>: View {
    let output: AttributedString
    let plainText: String
    @ViewBuilder let accessory: Accessory

    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            accessory
            Text(output)
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, BubbleMetrics.horizontalPadding)
        .padding(.vertical, 8)
        .background(.fill.secondary, in: .rect(cornerRadius: 17))
        .overlay(alignment: .topTrailing) {
            Button("Copiar salida", systemImage: "doc.on.doc") {
                Pasteboard.copy(plainText)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help("Copiar salida")
            .padding(6)
            .opacity(isHovering ? 1 : 0)
        }
        .onHover { isHovering = $0 }
        .padding(.trailing, BubbleMetrics.trailingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Salida")
    }
}

extension OutputBubble where Accessory == EmptyView {
    init(output: AttributedString, plainText: String) {
        self.init(output: output, plainText: plainText) { EmptyView() }
    }
}

// MARK: - Finished

private struct FinishedResponseView: View {
    let entry: CommandEntry
    let onRerun: () -> Void

    @State private var rendered: RenderedOutput?
    @State private var isShowingAll = false

    var body: some View {
        let rendered = rendered ?? RenderCache.shared[entry]
        VStack(alignment: .leading, spacing: 4) {
            if entry.kind == .interactive {
                InteractiveSummary(entry: entry)
            }
            if let rendered, !rendered.isEmpty {
                OutputBubble(output: rendered.preview, plainText: rendered.plainText) {
                    if rendered.isClipped {
                        Button("Mostrar las \(rendered.totalLines) líneas") {
                            isShowingAll = true
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
                .contextMenu {
                    Button("Copiar salida", systemImage: "doc.on.doc") { Pasteboard.copy(rendered.plainText) }
                    Button("Copiar comando", systemImage: "terminal") { Pasteboard.copy(entry.command) }
                    Button("Mostrar toda la salida", systemImage: "arrow.up.left.and.arrow.down.right") { isShowingAll = true }
                    Divider()
                    Button("Volver a ejecutar", systemImage: "arrow.clockwise", action: onRerun)
                }
            }
            ReceiptView(entry: entry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: entry.finishedAt) {
            guard RenderCache.shared[entry] == nil else { return }
            let output = entry.output
            let result = await RenderCache.render(output)
            RenderCache.shared[entry] = result
            self.rendered = result
        }
        .sheet(isPresented: $isShowingAll) {
            FullOutputSheet(command: entry.command, output: entry.output)
        }
    }
}

/// Small status line under a reply, like “Delivered” in Messages.
private struct ReceiptView: View {
    let entry: CommandEntry

    var body: some View {
        // The symbol shape (check vs. cross) carries the status, not only its color.
        HStack(spacing: 4) {
            if entry.wasInterrupted {
                Image(systemName: "stop.circle")
                Text("Interrumpido")
            } else if entry.succeeded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Completado")
            } else if let code = entry.exitCode {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Código \(code)")
            }
            if let duration = entry.duration, !entry.wasInterrupted {
                Text(duration.chatFormatted)
            }
            if entry.truncated {
                Text("· Salida recortada")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct InteractiveSummary: View {
    let entry: CommandEntry
    @AppStorage(AppSettings.fontSizeKey) private var fontSize = AppSettings.defaultFontSize
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sesión interactiva", systemImage: "rectangle.inset.filled.and.cursorarrow")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let transcript = entry.transcript {
                DisclosureGroup("Transcripción", isExpanded: $isExpanded) {
                    Text(transcript)
                        .font(.system(size: fontSize, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.secondary, in: .rect(cornerRadius: 17))
        .padding(.trailing, BubbleMetrics.trailingInset)
    }
}

// MARK: - Separators

private struct TimestampSeparator: View {
    let date: Date

    var body: some View {
        Text(date.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

private struct DirectoryChip: View {
    let directory: String

    var body: some View {
        Label(ShellEscape.abbreviate(directory), systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Carpeta \(ShellEscape.abbreviate(directory))")
    }
}

// MARK: - Helpers

enum Pasteboard {
    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

extension Duration {
    /// “0,2 s”, “12 s”, “3 min 4 s”.
    var chatFormatted: String {
        if self < .seconds(10) {
            let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
            return seconds.formatted(.number.precision(.fractionLength(1))) + " s"
        }
        return formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}

/// Rendered output cached across scrolling, so bubbles don't flicker as the
/// lazy stack recycles them.
final class RenderCache {
    static let shared = RenderCache()
    private let cache = NSCache<NSString, Box>()

    private final class Box {
        let value: RenderedOutput
        init(_ value: RenderedOutput) { self.value = value }
    }

    init() {
        cache.countLimit = 400
    }

    subscript(entry: CommandEntry) -> RenderedOutput? {
        get { cache.object(forKey: Self.key(entry))?.value }
        set {
            if let newValue { cache.setObject(Box(newValue), forKey: Self.key(entry)) }
        }
    }

    private static func key(_ entry: CommandEntry) -> NSString {
        "\(entry.id.uuidString)-\(entry.finishedAt?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    }

    @concurrent
    static func render(_ data: Data) async -> RenderedOutput {
        OutputRenderer.render(raw: [UInt8](data))
    }
}
