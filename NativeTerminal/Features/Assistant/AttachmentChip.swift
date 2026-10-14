import SwiftUI

/// A file attached to a request, shown as a small capsule.
struct AttachmentChip: View {
    let path: String
    var onRemove: (() -> Void)?

    var body: some View {
        let url = URL(filePath: path)
        let info = ToolInventory.info(for: url, relativeTo: "/")
        HStack(spacing: 4) {
            Image(systemName: Self.symbol(for: info.kind))
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            if info.size > 0 {
                Text(info.sizeText)
                    .foregroundStyle(.secondary)
            }
            if let onRemove {
                Button("Quitar", systemImage: "xmark.circle.fill", action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .pointerStyle(.link)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.fill.secondary, in: .capsule)
        .frame(maxWidth: 240)
        .help(path)
    }

    static func symbol(for kind: ToolInventory.FileInfo.Kind) -> String {
        switch kind {
        case .audio: "waveform"
        case .video: "film"
        case .image: "photo"
        case .folder: "folder"
        case .archive: "doc.zipper"
        case .other: "doc"
        }
    }
}
