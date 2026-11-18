import Foundation

nonisolated struct Completion: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case history
        case command
        case directory
        case file
        case subcommand, option, branch, script, signal, process

        var isContextual: Bool {
            switch self {
            case .history, .command, .directory, .file: false
            default: true
            }
        }
    }

    var title: String
    /// The whole command line after accepting this completion.
    var completion: String
    var kind: Kind

    var id: String { completion }

    /// What the candidate is, in plain words.
    @MainActor var detail: String {
        switch kind {
        case .history: String(localized: "Usado antes")
        case .command: CommandGlossary.describe(title) ?? String(localized: "Comando")
        case .directory: String(localized: "Carpeta")
        case .file: String(localized: "Archivo")
        case .subcommand: String(localized: "Subcomando")
        case .option: String(localized: "Opción")
        case .branch: String(localized: "Rama local")
        case .script: String(localized: "Script de npm")
        case .signal: String(localized: "Señal")
        case .process: String(localized: "Proceso")
        }
    }

    var systemImage: String {
        switch kind {
        case .history: "clock.arrow.circlepath"
        case .command: "apple.terminal"
        case .directory: "folder"
        case .file: "doc"
        case .subcommand, .script: "chevron.left.forwardslash.chevron.right"
        case .option: "slider.horizontal.3"
        case .branch: "arrow.triangle.branch"
        case .signal: "bolt"
        case .process: "waveform.path"
        }
    }
}
