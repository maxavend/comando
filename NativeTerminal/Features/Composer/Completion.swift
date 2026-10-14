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

    /// What the candidate is, in plain words.
    var detail: String {
        switch kind {
        case .history: String(localized: "Usado antes")
        case .command: CommandGlossary.describe(title) ?? String(localized: "Comando")
        case .directory: String(localized: "Carpeta")
        case .file: String(localized: "Archivo")
        }
    }

    var systemImage: String {
        switch kind {
        case .history: "clock.arrow.circlepath"
        case .command: "apple.terminal"
        case .directory: "folder"
        case .file: "doc"
        }
    }
}
