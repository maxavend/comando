import Foundation

struct Completion: Identifiable, Hashable {
    enum Kind: Hashable {
        case history
        case command
        case directory
        case file
    }

    var title: String
    /// The whole command line after accepting this completion.
    var completion: String
    var kind: Kind

    var id: String { completion }

    var systemImage: String {
        switch kind {
        case .history: "clock.arrow.circlepath"
        case .command: "apple.terminal"
        case .directory: "folder"
        case .file: "doc"
        }
    }
}
