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

    private static func key(_ entry: CommandEntry) -> NSString {
        "\(entry.id.uuidString)-\(entry.finishedAt?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    }

    @concurrent
    static func render(_ data: Data) async -> RenderedOutput {
        OutputRenderer.render(raw: [UInt8](data))
    }
}
