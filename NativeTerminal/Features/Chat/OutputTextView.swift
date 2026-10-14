import AppKit
import SwiftUI

/// Long output in a native text view, which handles large text far better
/// than a SwiftUI `Text`.
struct OutputTextView: NSViewRepresentable {
    let output: Data
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            // The container's own line padding is part of the inset, so text
            // starts exactly on the sheet's content margin.
            let linePadding = textView.textContainer?.lineFragmentPadding ?? 0
            textView.textContainerInset = NSSize(
                width: Metrics.contentInset - linePadding,
                height: Metrics.transcriptVerticalInset
            )
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.textStorage?.setAttributedString(
                OutputRenderer.fullAttributedString(raw: [UInt8](output), font: font)
            )
        }
        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {}
}
