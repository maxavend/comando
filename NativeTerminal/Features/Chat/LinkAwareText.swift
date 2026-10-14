import SwiftUI

/// Marks the parts of a `Text` that are links, so their on-screen bounds can be found.
private struct LinkMarker: TextAttribute {}

/// Selectable text whose links show the pointing-hand cursor on hover, like links
/// anywhere else in macOS. Text selection would otherwise show an I-beam everywhere.
struct LinkAwareText: View {
    let content: AttributedString

    @State private var linkRects: [CGRect] = []
    @State private var isOverLink = false

    var body: some View {
        Self.text(for: content)
            .onPreferenceChange(Text.LayoutKey.self) { layouts in
                let rects = Self.linkRects(in: layouts)
                if rects != linkRects { linkRects = rects }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let over = linkRects.contains { $0.insetBy(dx: -1, dy: -1).contains(location) }
                    if over != isOverLink { isOverLink = over }
                case .ended:
                    isOverLink = false
                }
            }
            .pointerStyle(isOverLink ? .link : nil)
    }

    /// Builds the text so each link run carries the marker attribute.
    private static func text(for content: AttributedString) -> Text {
        guard content.runs.contains(where: { $0.link != nil }) else { return Text(content) }
        var result = Text(verbatim: "")
        for (link, range) in content.runs[\.link] {
            let piece = Text(AttributedString(content[range]))
            result = Text("\(result)\(link == nil ? piece : piece.customAttribute(LinkMarker()))")
        }
        return result
    }

    private static func linkRects(in layouts: [Text.LayoutKey.AnchoredLayout]) -> [CGRect] {
        var rects: [CGRect] = []
        for anchored in layouts {
            for line in anchored.layout {
                for run in line where run[LinkMarker.self] != nil {
                    rects.append(run.typographicBounds.rect)
                }
            }
        }
        return rects
    }
}
