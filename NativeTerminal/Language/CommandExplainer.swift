import Foundation

/// One piece of a command line and what it means.
nonisolated struct CommandPart: Identifiable, Equatable, Sendable {
    let id: Int
    let token: String
    let explanation: String
}

/// Explains a command piece by piece: the program, its options and its arguments.
nonisolated enum CommandExplainer {
    static func parts(of command: String) -> [CommandPart] {
        var parts: [CommandPart] = []
        var program: String?
        var subcommand: String?
        for token in tokens(command) {
            let explanation: String
            if let connector = connectors[token] {
                explanation = connector
                program = nil
                subcommand = nil
            } else if program == nil {
                if token == "sudo" {
                    explanation = String(localized: "Ejecuta lo que sigue como administrador")
                } else if token.contains("=") && !token.hasPrefix("-") {
                    explanation = String(localized: "Define una variable solo para este comando")
                } else {
                    program = (token as NSString).lastPathComponent
                    explanation = CommandGlossary.describe(token) ?? String(localized: "El programa que se ejecuta")
                }
            } else if token.hasPrefix("-") {
                explanation = describeOption(token, program: program ?? "", subcommand: subcommand)
            } else if subcommand == nil, let table = subcommandPrograms[program ?? ""] {
                subcommand = token
                explanation = CommandGlossary.describe("\(program ?? "") \(token)") ?? table
            } else {
                explanation = describeArgument(token)
            }
            parts.append(CommandPart(id: parts.count, token: token, explanation: explanation))
        }
        return parts
    }

    // MARK: - Tokens

    /// Splits into shell words, keeping quotes and treating `|`, `>`, `&&`, `;` as tokens.
    static func tokens(_ command: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var characters = Array(command)[...]
        func flush() {
            if !current.isEmpty { result.append(current) }
            current = ""
        }
        while let character = characters.first {
            characters = characters.dropFirst()
            if let open = quote {
                current.append(character)
                if character == open { quote = nil }
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
                current.append(character)
            case " ", "\t", "\n":
                flush()
            case "|", ";", ">", "<", "&":
                flush()
                var symbol = String(character)
                if let next = characters.first, (next == character && character != ";") || (character == ">" && next == "&") {
                    symbol.append(next)
                    characters = characters.dropFirst()
                }
                result.append(symbol)
            case "\\":
                current.append(character)
                if let next = characters.first {
                    current.append(next)
                    characters = characters.dropFirst()
                }
            default:
                current.append(character)
            }
        }
        flush()
        return result
    }

    // MARK: - Descriptions

    private static let connectors: [String: String] = [
        "|": String(localized: "Pasa el resultado al comando siguiente"),
        "||": String(localized: "Si falla, ejecuta lo que sigue"),
        "&&": String(localized: "Si funciona, ejecuta lo que sigue"),
        ";": String(localized: "Después, ejecuta lo que sigue"),
        ">": String(localized: "Guarda el resultado en un archivo (lo reemplaza)"),
        ">>": String(localized: "Agrega el resultado al final de un archivo"),
        "<": String(localized: "Lee la entrada desde un archivo"),
        "&": String(localized: "Ejecuta en segundo plano"),
    ]

    private static let subcommandPrograms: [String: String] = [
        "git": String(localized: "La acción de Git"),
        "brew": String(localized: "La acción de Homebrew"),
        "npm": String(localized: "La acción de npm"),
    ]

    private static func describeArgument(_ token: String) -> String {
        if token.hasPrefix("'") || token.hasPrefix("\"") { return String(localized: "Un texto") }
        if token.contains("*") || token.contains("?") { return String(localized: "Un patrón: todos los nombres que coincidan") }
        if token.hasPrefix("http://") || token.hasPrefix("https://") { return String(localized: "Una dirección web") }
        if token == "." { return String(localized: "Esta carpeta") }
        if token == ".." { return String(localized: "La carpeta de arriba") }
        if token == "~" { return String(localized: "Tu carpeta de inicio") }
        if token.allSatisfy(\.isNumber) { return String(localized: "Un número") }
        if token.contains("/") || token.contains(".") || token.hasPrefix("~") { return String(localized: "Un archivo o carpeta") }
        return String(localized: "Un dato para el comando")
    }

    private static func describeOption(_ token: String, program: String, subcommand: String?) -> String {
        let table = options[subcommand.map { "\(program) \($0)" } ?? program] ?? options[program] ?? [:]
        if let exact = table[token] { return exact }
        // Combined short flags: -lhG → -l, -h, -G.
        if !token.hasPrefix("--"), token.count > 2 {
            let letters = token.dropFirst().map { "-\($0)" }
            let described = letters.compactMap { flag in table[flag].map { "\(flag): \($0)" } }
            if described.count == letters.count { return described.joined(separator: " · ") }
        }
        return String(localized: "Una opción que cambia cómo funciona")
    }

    private static let options: [String: [String: String]] = [
        "ls": ["-l": "en detalle", "-a": "incluye ocultos", "-h": "tamaños legibles", "-G": "con colores",
               "-t": "por fecha", "-r": "en orden inverso", "-R": "con subcarpetas", "-S": "por tamaño", "-1": "uno por línea"],
        "rm": ["-r": "incluye carpetas y su contenido", "-R": "incluye carpetas y su contenido", "-f": "sin preguntar", "-i": "pregunta antes de cada uno", "-v": "muestra lo que borra"],
        "cp": ["-r": "incluye carpetas", "-R": "incluye carpetas", "-i": "pregunta antes de reemplazar", "-v": "muestra lo que copia", "-p": "conserva fechas y permisos"],
        "mv": ["-i": "pregunta antes de reemplazar", "-n": "no reemplaza", "-v": "muestra lo que mueve"],
        "mkdir": ["-p": "crea también las carpetas intermedias"],
        "grep": ["-r": "busca en subcarpetas", "-n": "muestra el número de línea", "-i": "sin distinguir mayúsculas", "-v": "muestra lo que no coincide", "-l": "solo los nombres de archivo", "-w": "palabras completas", "-E": "patrones extendidos"],
        "find": ["-name": "por nombre", "-iname": "por nombre, sin distinguir mayúsculas", "-type": "por tipo (f archivo, d carpeta)", "-mtime": "por fecha de cambio", "-size": "por tamaño"],
        "du": ["-s": "un total por elemento", "-h": "tamaños legibles", "-d": "hasta cierta profundidad"],
        "df": ["-h": "tamaños legibles"],
        "head": ["-n": "cuántas líneas"],
        "tail": ["-n": "cuántas líneas", "-f": "sigue mostrando lo nuevo"],
        "sort": ["-r": "en orden inverso", "-n": "como números", "-h": "como tamaños (K, M, G)"],
        "ps": ["-A": "todos los procesos", "-o": "qué columnas mostrar", "-r": "por uso de CPU", "-a": "de todos los usuarios", "-x": "incluye los sin terminal", "-u": "con más detalle"],
        "chmod": ["-R": "incluye todo lo de dentro"],
        "curl": ["-L": "sigue redirecciones", "-o": "guarda en un archivo", "-O": "guarda con el nombre original", "-s": "sin mostrar progreso", "-S": "muestra errores", "-f": "falla si el servidor da error", "-I": "solo los encabezados"],
        "tar": ["-c": "crea un paquete", "-x": "extrae un paquete", "-z": "con compresión gzip", "-v": "muestra cada archivo", "-f": "el archivo del paquete"],
        "zip": ["-r": "incluye carpetas"],
        "ping": ["-c": "cuántos intentos"],
        "lsof": ["-i": "conexiones de red", "-n": "sin resolver nombres", "-P": "puertos como números"],
        "git": ["--version": "muestra la versión"],
        "git log": ["--oneline": "un commit por línea", "-n": "cuántos commits", "--graph": "con un dibujo de las ramas"],
        "git commit": ["-m": "con este mensaje", "-a": "incluye todos los cambios", "--amend": "corrige el último commit"],
        "git reset": ["--hard": "descarta los cambios", "--soft": "conserva los cambios"],
        "git push": ["--force": "reemplaza el historial remoto", "-f": "reemplaza el historial remoto", "-u": "recuerda a dónde subir"],
        "git checkout": ["-b": "crea una rama nueva"],
        "git switch": ["-c": "crea una rama nueva"],
        "git clean": ["-f": "sin preguntar", "-d": "incluye carpetas"],
        "npm install": ["-g": "para todo el sistema", "-D": "solo para desarrollo", "--save-dev": "solo para desarrollo"],
    ]
}
