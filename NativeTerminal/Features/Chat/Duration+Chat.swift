import AppKit
import SwiftUI

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
