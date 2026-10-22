import Foundation

/// The built-in recipes, searchable by what people want to do.
nonisolated enum RecipeBook {
    static func search(_ query: String) -> [Recipe] {
        all.filter { $0.matches(query) }
    }

    private static func q(_ value: String) -> String { ShellEscape.quote(value) }

    static let all: [Recipe] = [
        // MARK: Archivos y carpetas
        Recipe("list", title: "Ver qué hay en esta carpeta", detail: "Lista los archivos con su tamaño y fecha.",
               systemImage: "list.bullet", category: .files, keywords: ["listar", "archivos", "contenido"]) { _ in
            "ls -lhG"
        },
        Recipe("hidden", title: "Ver archivos ocultos", detail: "Incluye los que empiezan con punto, como .gitignore.",
               systemImage: "eye", category: .files, keywords: ["ocultos", "punto", "dotfiles"]) { _ in
            "ls -lhaG"
        },
        Recipe("mkdir", title: "Crear una carpeta", detail: "Crea una carpeta nueva aquí.",
               systemImage: "folder.badge.plus", category: .files, keywords: ["nueva", "directorio"],
               parameters: [RecipeParameter(id: "name", label: "Nombre", kind: .text, placeholder: "Nueva carpeta")]) { v in
            "mkdir " + q(v["name"]!)
        },
        Recipe("touch", title: "Crear un archivo vacío", detail: "Crea un archivo nuevo aquí.",
               systemImage: "doc.badge.plus", category: .files, keywords: ["nuevo", "texto"],
               parameters: [RecipeParameter(id: "name", label: "Nombre", kind: .text, placeholder: "notas.txt")]) { v in
            "touch " + q(v["name"]!)
        },
        Recipe("find", title: "Buscar archivos por nombre", detail: "Busca en esta carpeta y en las que tiene dentro.",
               systemImage: "magnifyingglass", category: .files, keywords: ["encontrar", "nombre"],
               parameters: [RecipeParameter(id: "text", label: "Parte del nombre", kind: .text, placeholder: "informe")]) { v in
            "find . -iname " + q("*\(v["text"]!)*")
        },
        Recipe("grep", title: "Buscar texto dentro de archivos", detail: "Muestra cada archivo y línea donde aparece el texto.",
               systemImage: "text.magnifyingglass", category: .files, keywords: ["contenido", "palabra", "grep"],
               parameters: [RecipeParameter(id: "text", label: "Texto", kind: .text, placeholder: "TODO")]) { v in
            "grep -rn " + q(v["text"]!) + " ."
        },
        Recipe("du", title: "Ver qué ocupa más espacio aquí", detail: "Ordena lo que hay en esta carpeta por tamaño.",
               systemImage: "chart.bar", category: .files, keywords: ["tamaño", "espacio", "pesado", "grande"]) { _ in
            "du -sh * | sort -rh | head -20"
        },
        Recipe("zip", title: "Comprimir una carpeta", detail: "Crea un archivo .zip con la carpeta elegida.",
               systemImage: "archivebox", category: .files, keywords: ["zip", "comprimir", "empaquetar"],
               parameters: [RecipeParameter(id: "folder", label: "Carpeta", kind: .folder, placeholder: "carpeta")]) { v in
            let name = (v["folder"]! as NSString).lastPathComponent
            return "zip -r " + q(name + ".zip") + " " + q(v["folder"]!)
        },
        Recipe("unzip", title: "Descomprimir un .zip", detail: "Extrae el contenido aquí.",
               systemImage: "archivebox.circle", category: .files, keywords: ["zip", "extraer", "descomprimir"],
               parameters: [RecipeParameter(id: "file", label: "Archivo .zip", kind: .file, placeholder: "archivo.zip")]) { v in
            "unzip " + q(v["file"]!)
        },
        Recipe("finder", title: "Abrir esta carpeta en Finder", detail: "Muestra la carpeta actual en una ventana de Finder.",
               systemImage: "macwindow", category: .files, keywords: ["finder", "abrir", "ventana"]) { _ in
            "open ."
        },
        Recipe("copypath", title: "Copiar la ruta de esta carpeta", detail: "Deja la ruta en el portapapeles.",
               systemImage: "doc.on.clipboard", category: .files, keywords: ["ruta", "path", "copiar"]) { _ in
            "pwd | pbcopy"
        },

        // MARK: Tu Mac
        Recipe("df", title: "Ver el espacio en disco", detail: "Cuánto espacio queda libre.",
               systemImage: "internaldrive", category: .system, keywords: ["disco", "libre", "almacenamiento"]) { _ in
            "df -h /"
        },
        Recipe("swvers", title: "Ver la versión de macOS", detail: "Nombre, versión y compilación del sistema.",
               systemImage: "info.circle", category: .system, keywords: ["versión", "sistema"]) { _ in
            "sw_vers"
        },
        Recipe("cpu", title: "Ver qué está usando más CPU", detail: "Los 10 programas que más procesador usan.",
               systemImage: "gauge.with.dots.needle.67percent", category: .system, keywords: ["lento", "procesos", "cpu", "procesador"]) { _ in
            "ps -Ao pid,pcpu,pmem,comm -r | head -11"
        },
        Recipe("memory", title: "Ver qué está usando más memoria", detail: "Los 10 programas que más RAM ocupan.",
               systemImage: "memorychip", category: .system, keywords: ["ram", "memoria", "procesos", "lento"]) { _ in
            "ps -Ao pid,pmem,rss,comm -m | head -11"
        },
        Recipe("date", title: "Ver la fecha y la hora", detail: "La fecha y hora de este Mac.",
               systemImage: "clock", category: .system, keywords: ["hora", "fecha", "dia", "hoy"]) { _ in
            "date"
        },
        Recipe("battery", title: "Ver el estado de la batería", detail: "Porcentaje y si está cargando.",
               systemImage: "battery.75percent", category: .system, keywords: ["batería", "carga"]) { _ in
            "pmset -g batt"
        },
        Recipe("caffeinate", title: "Evitar que el Mac se duerma", detail: "Mantiene el Mac despierto hasta que lo detengas.",
               systemImage: "cup.and.saucer", category: .system, keywords: ["dormir", "reposo", "despierto"]) { _ in
            "caffeinate -d"
        },

        // MARK: Red
        Recipe("port", title: "Ver qué programa usa un puerto", detail: "Útil cuando un servidor dice que el puerto está ocupado.",
               systemImage: "network", category: .network, keywords: ["puerto", "ocupado", "port", "lsof"],
               parameters: [RecipeParameter(id: "port", label: "Puerto", kind: .number, placeholder: "3000")]) { v in
            "lsof -nP -iTCP:" + v["port"]!.filter(\.isNumber) + " -sTCP:LISTEN"
        },
        Recipe("ip", title: "Ver mi dirección IP local", detail: "La dirección de este Mac en tu red Wi‑Fi.",
               systemImage: "wifi", category: .network, keywords: ["ip", "dirección", "red"]) { _ in
            "ipconfig getifaddr en0"
        },
        Recipe("speed", title: "Medir la velocidad de internet", detail: "Mide la bajada, la subida y la respuesta con la herramienta de macOS.",
               systemImage: "speedometer", category: .network, keywords: ["velocidad", "internet", "conexion", "lento", "speedtest", "wifi"]) { _ in
            "networkQuality"
        },
        Recipe("dns", title: "Vaciar la caché de DNS", detail: "Ayuda cuando una página no carga tras cambiar de dirección. Pide tu contraseña.",
               systemImage: "arrow.clockwise.icloud", category: .network, keywords: ["dns", "cache", "flush", "internet", "pagina"]) { _ in
            "sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
        },
        Recipe("ping", title: "Probar la conexión a internet", detail: "Envía 4 mensajes de prueba a apple.com.",
               systemImage: "antenna.radiowaves.left.and.right", category: .network, keywords: ["internet", "conexión", "ping"]) { _ in
            "ping -c 4 apple.com"
        },
        Recipe("serve", title: "Compartir esta carpeta como sitio web", detail: "Inicia un servidor local; ábrelo en el navegador.",
               systemImage: "globe", category: .network, keywords: ["servidor", "web", "http", "local"],
               parameters: [RecipeParameter(id: "port", label: "Puerto", kind: .number, placeholder: "8000", defaultValue: "8000")]) { v in
            "python3 -m http.server " + v["port"]!.filter(\.isNumber)
        },

        // MARK: Desarrollo
        Recipe("gitstatus", title: "Ver los cambios del proyecto", detail: "Qué archivos cambiaste desde el último commit.",
               systemImage: "arrow.triangle.branch", category: .development, keywords: ["git", "cambios", "estado"]) { _ in
            "git status"
        },
        Recipe("gitlog", title: "Ver el historial reciente", detail: "Los últimos 15 commits, uno por línea.",
               systemImage: "clock.arrow.circlepath", category: .development, keywords: ["git", "historial", "commits"]) { _ in
            "git log --oneline -15"
        },
        Recipe("npminstall", title: "Instalar las dependencias", detail: "Descarga lo que el proyecto necesita (npm).",
               systemImage: "shippingbox", category: .development, keywords: ["npm", "node", "instalar", "dependencias"]) { _ in
            "npm install"
        },
        Recipe("npmrun", title: "Ver los scripts del proyecto", detail: "Lista los comandos que define package.json.",
               systemImage: "list.bullet.rectangle", category: .development, keywords: ["npm", "scripts", "package.json"]) { _ in
            "npm run"
        },
        Recipe("versions", title: "Ver versiones de Node y Python", detail: "Qué versiones están instaladas.",
               systemImage: "number", category: .development, keywords: ["node", "python", "versión"]) { _ in
            "node -v; python3 --version"
        },
    ]
}
