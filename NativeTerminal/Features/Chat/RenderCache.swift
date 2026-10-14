import AppKit
import SwiftUI

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

    /// Output small enough to render while laying out, so the bubble has its
    /// final height from the first frame and the transcript doesn't jump.
    static let synchronousLimit = 64 * 1024

    /// The cached rendering, or a synchronous one when the output is small.
    func immediate(for entry: CommandEntry) -> RenderedOutput? {
        if let cached = self[entry] { return cached }
        guard entry.output.count <= Self.synchronousLimit else { return nil }
        let rendered = Self.linked(OutputRenderer.render(raw: [UInt8](entry.output)), for: entry)
        self[entry] = rendered
        return rendered
    }

    /// Makes the names in `ls` output clickable links to the files.
    static func linked(_ rendered: RenderedOutput, for entry: CommandEntry) -> RenderedOutput {
        guard let folder = OutputLinker.listedFolder(command: entry.command, directory: entry.directory) else { return rendered }
        var linked = rendered
        linked.preview = OutputLinker.linkify(rendered.preview, folder: folder)
        return linked
    }

    private static func key(_ entry: CommandEntry) -> NSString {
        "\(entry.id.uuidString)-\(entry.finishedAt?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    }

    @concurrent
    static func render(_ data: Data) async -> RenderedOutput {
        OutputRenderer.render(raw: [UInt8](data))
    }
}
