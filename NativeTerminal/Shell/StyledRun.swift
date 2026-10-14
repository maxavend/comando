import AppKit
import SwiftUI

/// A run of characters sharing one style.
nonisolated struct StyledRun: Sendable, Equatable {
    var text: String
    var style: TextStyle
}
