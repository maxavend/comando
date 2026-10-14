import AppKit
import SwiftTerm
import SwiftUI

struct OutputTextView: NSViewRepresentable {
    let output: Data
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 12, height: 12)
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            textView.textStorage?.setAttributedString(
                OutputRenderer.fullAttributedString(raw: [UInt8](output), font: font)
            )
        }
        return scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {}
}
