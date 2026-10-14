import Foundation

/// A well-known tool worth recommending, with what it is for in plain words.
nonisolated struct CatalogTool: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case media = "Audio, video e imágenes"
        case documents = "Documentos y PDF"
        case web = "Internet y descargas"
        case developer = "Programación"
        case files = "Archivos y sistema"
    }

    /// Homebrew package name.
    var id: String
    /// The command it adds, when it differs from the package name.
    var command: String
    var title: String
    var detail: String
    var category: Category
    var systemImage: String
    /// Words people use when they need it (accent-free, lowercase).
    var keywords: [String]
    var isCask = false
    /// An example of use, shown once it is installed.
    var example: String?

    init(_ id: String, command: String? = nil, title: String, detail: String, category: Category,
         systemImage: String, keywords: [String], isCask: Bool = false, example: String? = nil) {
        self.id = id
        self.command = command ?? id
        self.title = title
        self.detail = detail
        self.category = category
        self.systemImage = systemImage
        self.keywords = keywords
        self.isCask = isCask
        self.example = example
    }

    var installCommand: String {
        isCask ? "brew install --cask \(id)" : "brew install \(id)"
    }
}

/// Tools that cover most everyday needs, so the assistant can recommend one
/// (and install it) when nothing on the Mac does the job.
nonisolated enum ToolCatalog {
    static let all: [CatalogTool] = [
        CatalogTool("ffmpeg", title: "FFmpeg", detail: "Convierte, comprime y recorta cualquier audio o video.",
                    category: .media, systemImage: "film",
                    keywords: ["audio", "video", "mp3", "mp4", "convertir", "recortar", "comprimir", "sonido", "extraer audio", "gif"],
                    example: "ffmpeg -i entrada.mov salida.mp4"),
        CatalogTool("imagemagick", command: "magick", title: "ImageMagick", detail: "Convierte, recorta y edita imágenes en lote.",
                    category: .media, systemImage: "photo.on.rectangle",
                    keywords: ["imagen", "imagenes", "foto", "fotos", "png", "jpg", "convertir imagen", "recortar imagen", "marca de agua", "en lote"],
                    example: "magick foto.heic foto.jpg"),
        CatalogTool("pngquant", title: "pngquant", detail: "Reduce mucho el peso de imágenes PNG sin que se note.",
                    category: .media, systemImage: "photo",
                    keywords: ["png", "optimizar", "peso imagen", "comprimir imagen", "comprimir png"],
                    example: "pngquant imagen.png"),
        CatalogTool("webp", command: "cwebp", title: "WebP", detail: "Convierte imágenes a WebP, el formato liviano para la web.",
                    category: .media, systemImage: "photo.badge.arrow.down",
                    keywords: ["webp", "imagen web", "optimizar web"],
                    example: "cwebp foto.jpg -o foto.webp"),
        CatalogTool("exiftool", title: "ExifTool", detail: "Lee y borra los metadatos de fotos y videos (ubicación, cámara…).",
                    category: .media, systemImage: "info.circle",
                    keywords: ["metadatos", "exif", "ubicacion de la foto", "gps", "datos de la foto"],
                    example: "exiftool foto.jpg"),
        CatalogTool("yt-dlp", title: "yt-dlp", detail: "Descarga videos y audio de YouTube y otros sitios.",
                    category: .web, systemImage: "arrow.down.circle",
                    keywords: ["youtube", "de youtube", "descarg", "bajar un video", "bajar video", "vimeo", "tiktok", "instagram"],
                    example: "yt-dlp 'https://youtu.be/…'"),
        CatalogTool("wget", title: "Wget", detail: "Descarga archivos o sitios completos desde internet.",
                    category: .web, systemImage: "arrow.down.doc",
                    keywords: ["descargar archivo", "descargar un archivo", "bajar archivo", "bajar un archivo", "wget", "sitio completo", "descargar pagina"],
                    example: "wget https://ejemplo.com/archivo.zip"),
        CatalogTool("httpie", command: "http", title: "HTTPie", detail: "Prueba APIs con comandos fáciles de leer.",
                    category: .web, systemImage: "network",
                    keywords: ["api", "peticion", "request", "endpoint", "rest", "probar api"],
                    example: "http GET https://api.github.com"),
        CatalogTool("pandoc", title: "Pandoc", detail: "Convierte documentos entre Word, Markdown, PDF, HTML y más.",
                    category: .documents, systemImage: "doc.text",
                    keywords: ["word", "docx", "markdown", "convertir documento", "html a", "a pdf", "epub"],
                    example: "pandoc notas.md -o notas.docx"),
        CatalogTool("ghostscript", command: "gs", title: "Ghostscript", detail: "Comprime y une archivos PDF.",
                    category: .documents, systemImage: "doc.richtext",
                    keywords: ["pdf", "comprimir pdf", "achicar pdf", "unir pdf", "peso pdf"],
                    example: "gs -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook -o chico.pdf grande.pdf"),
        CatalogTool("qpdf", title: "qpdf", detail: "Separa, une, rota y quita contraseñas de PDF.",
                    category: .documents, systemImage: "doc.on.doc",
                    keywords: ["pdf", "separar pdf", "dividir pdf", "rotar pdf", "contrasena pdf", "paginas pdf"],
                    example: "qpdf --empty --pages a.pdf b.pdf -- unido.pdf"),
        CatalogTool("ocrmypdf", title: "OCRmyPDF", detail: "Hace que el texto de un PDF escaneado se pueda buscar y copiar.",
                    category: .documents, systemImage: "text.viewfinder",
                    keywords: ["ocr", "escaneado", "texto de un pdf", "reconocer texto"],
                    example: "ocrmypdf escaneo.pdf escaneo-texto.pdf"),
        CatalogTool("tesseract", title: "Tesseract", detail: "Saca el texto de una imagen.",
                    category: .documents, systemImage: "text.viewfinder",
                    keywords: ["ocr", "texto de una imagen", "leer imagen", "extraer texto"],
                    example: "tesseract captura.png salida"),
        CatalogTool("jq", title: "jq", detail: "Lee, filtra y ordena archivos JSON.",
                    category: .developer, systemImage: "curlybraces",
                    keywords: ["json", "filtrar json", "formatear json"],
                    example: "jq '.' datos.json"),
        CatalogTool("gh", title: "GitHub CLI", detail: "Crea repositorios, PRs e issues de GitHub sin salir de la terminal.",
                    category: .developer, systemImage: "arrow.triangle.branch",
                    keywords: ["github", "pull request", "issue", "repositorio", "repo"],
                    example: "gh repo create"),
        CatalogTool("node", title: "Node.js", detail: "Ejecuta JavaScript y trae npm para instalar paquetes.",
                    category: .developer, systemImage: "chevron.left.forwardslash.chevron.right",
                    keywords: ["node", "javascript", "npm", "npx"],
                    example: "node --version"),
        CatalogTool("python", command: "python3", title: "Python", detail: "La versión más reciente de Python.",
                    category: .developer, systemImage: "chevron.left.forwardslash.chevron.right",
                    keywords: ["python", "pip", "script de python"],
                    example: "python3 --version"),
        CatalogTool("uv", title: "uv", detail: "Instala Python y sus herramientas de forma rápida y ordenada.",
                    category: .developer, systemImage: "shippingbox",
                    keywords: ["pip", "entorno virtual", "venv", "paquetes de python"],
                    example: "uv tool install ruff"),
        CatalogTool("ripgrep", command: "rg", title: "ripgrep", detail: "Busca texto dentro de miles de archivos en segundos.",
                    category: .files, systemImage: "magnifyingglass",
                    keywords: ["buscar texto", "buscar en archivos", "grep", "encontrar palabra"],
                    example: "rg 'texto a buscar'"),
        CatalogTool("fd", title: "fd", detail: "Encuentra archivos por nombre, rápido y fácil.",
                    category: .files, systemImage: "doc.text.magnifyingglass",
                    keywords: ["buscar archivo", "encontrar archivo", "find"],
                    example: "fd informe"),
        CatalogTool("tree", title: "tree", detail: "Muestra una carpeta y sus subcarpetas como árbol.",
                    category: .files, systemImage: "list.bullet.indent",
                    keywords: ["arbol", "estructura de carpetas", "ver carpetas"],
                    example: "tree -L 2"),
        CatalogTool("ncdu", title: "ncdu", detail: "Muestra qué carpetas ocupan más espacio y ayuda a liberarlo.",
                    category: .files, systemImage: "internaldrive",
                    keywords: ["espacio", "disco lleno", "ocupa", "liberar espacio", "que pesa"],
                    example: "ncdu ~"),
        CatalogTool("btop", title: "btop", detail: "Monitor bonito de CPU, memoria, disco y red.",
                    category: .files, systemImage: "gauge.with.dots.needle.67percent",
                    keywords: ["cpu", "memoria", "procesos", "monitor", "rendimiento", "ram"],
                    example: "btop"),
        CatalogTool("tldr", title: "tldr", detail: "Ejemplos cortos de cómo usar cualquier comando.",
                    category: .files, systemImage: "questionmark.circle",
                    keywords: ["como se usa", "ejemplos de comandos", "ayuda de un comando", "manual"],
                    example: "tldr tar"),
        CatalogTool("rclone", title: "rclone", detail: "Copia y sincroniza archivos con Google Drive, Dropbox, S3 y más.",
                    category: .web, systemImage: "icloud.and.arrow.up",
                    keywords: ["google drive", "dropbox", "s3", "nube", "sincronizar", "respaldo"],
                    example: "rclone config"),
    ]

    static func tool(named id: String) -> CatalogTool? {
        all.first { $0.id == id || $0.command == id }
    }

    /// The tool that best fits a request, if one clearly does.
    static func match(_ request: String, minimumScore: Int = 2) -> CatalogTool? {
        let words = AssistantEngine.normalized(request)
        let scored = all.map { ($0, score($0, for: words)) }
        return scored.filter { $0.1 >= minimumScore }.max { $0.1 < $1.1 }?.0
    }

    /// How strongly normalized request words point at a tool. Phrases weigh
    /// more than single words, and naming the tool weighs most.
    static func score(_ tool: CatalogTool, for normalizedWords: String) -> Int {
        let request = AssistantEngine.keywords(in: normalizedWords)
        var score = tool.keywords.reduce(0) { total, keyword in
            // Every meaningful word of the keyword must be in the request, in
            // any form (“comprime un pdf” matches “comprimir pdf”).
            let parts = AssistantEngine.keywords(in: keyword)
            guard !parts.isEmpty, parts.allSatisfy({ part in request.contains { sameStem($0, part) } }) else { return total }
            return total + (parts.count > 1 ? 3 : 2)
        }
        if request.contains(tool.id) || request.contains(tool.command) { score += 4 }
        return score
    }

    /// “comprime” and “comprimir” share a stem; short words must match exactly.
    static func sameStem(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let common = zip(a, b).prefix { $0 == $1 }.count
        return common >= 5 || (common >= 4 && min(a.count, b.count) <= 5 && common == min(a.count, b.count))
    }

    /// A more capable tool to mention next to a built-in one.
    static func upgrade(for action: AssistantAction) -> CatalogTool? {
        switch action {
        case .compressAudio, .compressVideo: tool(named: "ffmpeg")
        case .resizeImage: tool(named: "imagemagick")
        default: nil
        }
    }
}
