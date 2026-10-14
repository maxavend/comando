import Foundation

/// Plain-language descriptions of common commands, shown under the command bubble.
nonisolated enum CommandGlossary {
    static func describe(_ command: String) -> String? {
        var words = command.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        // Skip environment assignments (FOO=1 cmd) and sudo.
        while let first = words.first, first.contains("=") && !first.hasPrefix("-") { words.removeFirst() }
        var prefix = ""
        if words.first == "sudo" {
            words.removeFirst()
            prefix = String(localized: "Como administrador: ")
        }
        guard let name = words.first.map({ String($0.split(separator: "/").last ?? "") }), !name.isEmpty else { return nil }
        let subcommand = words.dropFirst().first { !$0.hasPrefix("-") }

        if let table = subcommands[name], let subcommand, let description = table[subcommand] {
            return prefix + description
        }
        guard let description = commands[name] else { return nil }
        return prefix + description
    }

    private static let commands: [String: String] = [
        "ls": String(localized: "Listar archivos"),
        "cd": String(localized: "Cambiar de carpeta"),
        "pwd": String(localized: "Mostrar la carpeta actual"),
        "mkdir": String(localized: "Crear una carpeta"),
        "rmdir": String(localized: "Eliminar una carpeta vacía"),
        "rm": String(localized: "Eliminar archivos"),
        "trash": String(localized: "Mover a la Papelera"),
        "cp": String(localized: "Copiar archivos"),
        "mv": String(localized: "Mover o renombrar"),
        "touch": String(localized: "Crear un archivo vacío"),
        "cat": String(localized: "Mostrar el contenido de un archivo"),
        "less": String(localized: "Leer un archivo largo"),
        "head": String(localized: "Mostrar el inicio de un archivo"),
        "tail": String(localized: "Mostrar el final de un archivo"),
        "open": String(localized: "Abrir con la app predeterminada"),
        "echo": String(localized: "Mostrar un texto"),
        "printf": String(localized: "Mostrar un texto con formato"),
        "grep": String(localized: "Buscar texto"),
        "find": String(localized: "Buscar archivos"),
        "which": String(localized: "Ubicar un programa"),
        "man": String(localized: "Ver el manual de un comando"),
        "history": String(localized: "Ver comandos anteriores"),
        "clear": String(localized: "Limpiar la conversación"),
        "ssh": String(localized: "Conectarse a otro equipo"),
        "scp": String(localized: "Copiar archivos a otro equipo"),
        "curl": String(localized: "Consultar o descargar una URL"),
        "ping": String(localized: "Probar la conexión con un equipo"),
        "vim": String(localized: "Editar un archivo"),
        "nano": String(localized: "Editar un archivo"),
        "top": String(localized: "Ver los procesos en uso"),
        "htop": String(localized: "Ver los procesos en uso"),
        "ps": String(localized: "Listar procesos"),
        "kill": String(localized: "Terminar un proceso"),
        "df": String(localized: "Ver el espacio en disco"),
        "du": String(localized: "Ver cuánto ocupa una carpeta"),
        "sw_vers": String(localized: "Ver la versión de macOS"),
        "uname": String(localized: "Ver información del sistema"),
        "whoami": String(localized: "Ver tu usuario"),
        "date": String(localized: "Ver la fecha y la hora"),
        "zip": String(localized: "Comprimir archivos"),
        "unzip": String(localized: "Descomprimir un archivo"),
        "tar": String(localized: "Empaquetar o desempaquetar archivos"),
        "chmod": String(localized: "Cambiar permisos"),
        "python3": String(localized: "Ejecutar Python"),
        "python": String(localized: "Ejecutar Python"),
        "node": String(localized: "Ejecutar Node.js"),
        "seq": String(localized: "Generar una secuencia de números"),
        "sleep": String(localized: "Esperar unos segundos"),
        "false": String(localized: "Terminar con error (prueba)"),
        "true": String(localized: "Terminar sin error (prueba)"),
        "say": String(localized: "Leer un texto en voz alta"),
        "pbcopy": String(localized: "Copiar al portapapeles"),
        "pbpaste": String(localized: "Pegar desde el portapapeles"),
        "git": String(localized: "Control de versiones con Git"),
        "brew": String(localized: "Gestionar programas con Homebrew"),
        "npm": String(localized: "Gestionar paquetes de Node.js"),
        "xcodebuild": String(localized: "Compilar con Xcode"),
    ]

    private static let subcommands: [String: [String: String]] = [
        "git": [
            "status": String(localized: "Ver los cambios del repositorio"),
            "log": String(localized: "Ver el historial de cambios"),
            "diff": String(localized: "Ver las diferencias"),
            "add": String(localized: "Preparar cambios para guardar"),
            "commit": String(localized: "Guardar los cambios"),
            "push": String(localized: "Subir los cambios"),
            "pull": String(localized: "Traer los últimos cambios"),
            "clone": String(localized: "Descargar un repositorio"),
            "checkout": String(localized: "Cambiar de rama o restaurar archivos"),
            "switch": String(localized: "Cambiar de rama"),
            "branch": String(localized: "Ver o crear ramas"),
            "merge": String(localized: "Unir una rama"),
            "stash": String(localized: "Guardar cambios temporalmente"),
            "init": String(localized: "Crear un repositorio"),
            "fetch": String(localized: "Consultar cambios remotos"),
        ],
        "brew": [
            "install": String(localized: "Instalar un programa"),
            "uninstall": String(localized: "Desinstalar un programa"),
            "update": String(localized: "Actualizar Homebrew"),
            "upgrade": String(localized: "Actualizar programas"),
            "list": String(localized: "Ver programas instalados"),
            "search": String(localized: "Buscar un programa"),
        ],
        "npm": [
            "install": String(localized: "Instalar dependencias"),
            "run": String(localized: "Ejecutar un script del proyecto"),
            "test": String(localized: "Ejecutar las pruebas"),
            "start": String(localized: "Iniciar el proyecto"),
        ],
    ]
}
