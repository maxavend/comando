import Foundation

/// Why a command deserves a second look before running.
nonisolated struct CommandRisk: Equatable, Sendable {
    var title: String
    var explanation: String
}

/// Spots commands that are hard to undo, and explains the risk in plain words.
nonisolated enum DangerDetector {
    static func risk(of command: String) -> CommandRisk? {
        let line = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = line.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard !words.isEmpty else { return nil }

        // A script downloaded and run directly.
        if line.range(of: #"(curl|wget)[^|]*\|\s*(sudo\s+)?(sh|bash|zsh)\b"#, options: .regularExpression) != nil {
            return CommandRisk(
                title: String(localized: "Este comando descarga y ejecuta un programa de internet"),
                explanation: String(localized: "El programa se ejecutará sin que puedas revisarlo antes. Hazlo solo si confías en el sitio.")
            )
        }

        var arguments = words
        let usesSudo = arguments.first == "sudo"
        if usesSudo { arguments.removeFirst() }
        let name = arguments.first.map { String($0.split(separator: "/").last ?? "") } ?? ""
        let flags = arguments.dropFirst().filter { $0.hasPrefix("-") }.joined()

        switch name {
        case "rm":
            let recursive = flags.contains("r") || flags.contains("R")
            let wildcard = arguments.dropFirst().contains { $0.contains("*") }
            if recursive || wildcard {
                return CommandRisk(
                    title: String(localized: "Este comando borra archivos de forma permanente"),
                    explanation: recursive
                        ? String(localized: "Borra carpetas completas con todo su contenido. No pasa por la Papelera y no se puede deshacer.")
                        : String(localized: "Borra todos los archivos que coincidan con el patrón. No pasa por la Papelera y no se puede deshacer.")
                )
            }
        case "dd", "mkfs", "newfs_apfs", "newfs_hfs":
            return CommandRisk(
                title: String(localized: "Este comando escribe directamente en un disco"),
                explanation: String(localized: "Un error puede borrar un disco completo.")
            )
        case "diskutil" where arguments.contains(where: { ["erasedisk", "erasevolume", "partitiondisk", "zerodisk"].contains($0.lowercased()) }):
            return CommandRisk(
                title: String(localized: "Este comando borra un disco"),
                explanation: String(localized: "Todo el contenido del disco se perderá.")
            )
        case "git":
            let rest = arguments.dropFirst().joined(separator: " ")
            if rest.hasPrefix("reset") && rest.contains("--hard") {
                return CommandRisk(
                    title: String(localized: "Este comando descarta tus cambios"),
                    explanation: String(localized: "Los cambios que no guardaste con commit se perderán.")
                )
            }
            if rest.hasPrefix("clean") && flags.contains("f") {
                return CommandRisk(
                    title: String(localized: "Este comando borra archivos que Git no conoce"),
                    explanation: String(localized: "Los archivos nuevos que no agregaste al repositorio se borrarán.")
                )
            }
            if rest.hasPrefix("push") && (rest.contains("--force") || flags.contains("f")) {
                return CommandRisk(
                    title: String(localized: "Este comando reemplaza el historial remoto"),
                    explanation: String(localized: "Puede borrar cambios que otras personas subieron.")
                )
            }
        case "shutdown", "reboot", "halt":
            return CommandRisk(
                title: String(localized: "Este comando apaga o reinicia el Mac"),
                explanation: String(localized: "Las apps abiertas se cerrarán y podrías perder trabajo sin guardar.")
            )
        case "chmod", "chown":
            if flags.contains("R") {
                return CommandRisk(
                    title: String(localized: "Este comando cambia permisos de muchos archivos"),
                    explanation: String(localized: "Cambia todo lo que hay dentro de la carpeta. Si te equivocas, algunas apps podrían dejar de funcionar.")
                )
            }
        case "kill", "killall":
            if flags.contains("9") {
                return CommandRisk(
                    title: String(localized: "Este comando cierra un programa a la fuerza"),
                    explanation: String(localized: "El programa no podrá guardar su trabajo antes de cerrarse.")
                )
            }
        default:
            break
        }

        if usesSudo {
            return CommandRisk(
                title: String(localized: "Este comando se ejecuta como administrador"),
                explanation: String(localized: "Tendrá acceso a todo el sistema y te pedirá tu contraseña. Úsalo solo si sabes qué hace.")
            )
        }
        return nil
    }
}
