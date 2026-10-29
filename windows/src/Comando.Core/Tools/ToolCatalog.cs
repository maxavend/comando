using System.Globalization;
using System.Text;

namespace Comando.Core.Tools;

public enum ToolCategory
{
    Media,
    Documents,
    Web,
    Developer,
    Files,
}

/// <summary>A well-known tool worth recommending, with what it's for in plain words.</summary>
/// <param name="Id">The winget id (or the package name for <see cref="Manager"/>).</param>
/// <param name="Title">The name people know it by.</param>
/// <param name="Detail">What it's for, in one line.</param>
/// <param name="Category">Where it shows in the Discover list.</param>
/// <param name="Glyph">A Segoe Fluent Icons glyph.</param>
/// <param name="Commands">The commands it adds to the shell; the first is the main one.</param>
/// <param name="Keywords">Words people use when they need it (lowercase, without accents).</param>
public sealed record CatalogTool(
    string Id,
    string Title,
    string Detail,
    ToolCategory Category,
    string Glyph,
    IReadOnlyList<string> Commands,
    IReadOnlyList<string> Keywords)
{
    public PackageManager Manager { get; init; } = PackageManager.Winget;

    /// <summary>An example of use, shown once it's installed.</summary>
    public string? Example { get; init; }

    /// <summary>A command that installs it some other way, when no package manager has it.</summary>
    public string? CustomInstallCommand { get; init; }

    public string Command => Commands.Count > 0 ? Commands[0] : Id;

    public string InstallCommand => CustomInstallCommand ?? Manager.InstallCommand(Id);
}

/// <summary>
/// Tools that cover most everyday needs on Windows, so the Tools window and
/// the assistant can recommend one (and install it) when nothing on the PC
/// does the job.
/// </summary>
public static class ToolCatalog
{
    public static string DisplayName(this ToolCategory category) => category switch
    {
        ToolCategory.Media => "Audio, video e imágenes",
        ToolCategory.Documents => "Documentos y PDF",
        ToolCategory.Web => "Internet y descargas",
        ToolCategory.Developer => "Programación",
        ToolCategory.Files => "Archivos y sistema",
        _ => category.ToString(),
    };

    private static CatalogTool T(string id, string title, string detail, ToolCategory category, string glyph, string[] commands, string[] keywords, string? example = null) =>
        new(id, title, detail, category, glyph, commands, keywords) { Example = example };

    public static readonly IReadOnlyList<CatalogTool> All =
    [
        // Audio, video e imágenes
        T("Gyan.FFmpeg", "FFmpeg", "Convierte, comprime y recorta cualquier audio o video.", ToolCategory.Media, "",
            ["ffmpeg", "ffprobe"], ["audio", "video", "mp3", "mp4", "convertir", "recortar", "comprimir", "sonido", "extraer audio", "gif"],
            "ffmpeg -i entrada.mov salida.mp4"),
        T("ImageMagick.ImageMagick", "ImageMagick", "Convierte, recorta y edita imágenes en lote.", ToolCategory.Media, "",
            ["magick"], ["imagen", "imagenes", "foto", "fotos", "png", "jpg", "heic", "convertir imagen", "recortar imagen", "marca de agua", "en lote"],
            "magick foto.heic foto.jpg"),
        T("yt-dlp.yt-dlp", "yt-dlp", "Descarga videos y audio de YouTube y cientos de sitios.", ToolCategory.Media, "",
            ["yt-dlp"], ["youtube", "descargar video", "bajar video", "descargar audio", "musica", "podcast"],
            "yt-dlp -x --audio-format mp3 URL"),
        T("VideoLAN.VLC", "VLC", "Reproduce casi cualquier formato de audio y video.", ToolCategory.Media, "",
            ["vlc"], ["reproducir", "video", "pelicula", "mkv", "reproductor"]),
        T("HandBrake.HandBrake.CLI", "HandBrake CLI", "Comprime videos con buena calidad y poco peso.", ToolCategory.Media, "",
            ["HandBrakeCLI"], ["comprimir video", "reducir video", "mp4", "mkv", "dvd"]),
        T("Xiph.Opus", "Opus Tools", "Codifica audio en Opus, liviano y de buena calidad.", ToolCategory.Media, "",
            ["opusenc"], ["audio", "opus", "comprimir audio", "voz"]),
        T("OliverBetz.ExifTool", "ExifTool", "Lee y edita los metadatos de fotos y videos.", ToolCategory.Media, "",
            ["exiftool"], ["metadatos", "exif", "fecha foto", "gps", "camara"]),

        // Documentos y PDF
        T("JohnMacFarlane.Pandoc", "Pandoc", "Convierte documentos entre Markdown, Word, HTML, PDF y más.", ToolCategory.Documents, "",
            ["pandoc"], ["convertir documento", "markdown", "word", "docx", "html", "epub", "pdf"],
            "pandoc notas.md -o notas.docx"),
        T("ArtifexSoftware.GhostScript", "Ghostscript", "Comprime, une y convierte archivos PDF.", ToolCategory.Documents, "",
            ["gswin64c"], ["pdf", "comprimir pdf", "reducir pdf", "unir pdf", "postscript"]),
        T("oschwartz10612.Poppler", "Poppler", "Extrae texto e imágenes de PDF y los divide en páginas.", ToolCategory.Documents, "",
            ["pdftotext", "pdfimages", "pdfseparate", "pdfunite"], ["pdf", "extraer texto", "texto de pdf", "separar pdf", "unir pdf", "paginas"]),
        T("qpdf.qpdf", "qpdf", "Une, separa, rota y desbloquea PDF sin perder calidad.", ToolCategory.Documents, "",
            ["qpdf"], ["pdf", "unir pdf", "rotar pdf", "contrasena pdf", "desbloquear pdf"]),
        T("UB-Mannheim.TesseractOCR", "Tesseract", "Reconoce el texto de imágenes y documentos escaneados.", ToolCategory.Documents, "",
            ["tesseract"], ["ocr", "texto de imagen", "escaneo", "escaneado", "reconocer texto"]),
        T("TheDocumentFoundation.LibreOffice", "LibreOffice", "Abre y convierte documentos de Office, también desde la terminal.", ToolCategory.Documents, "",
            ["soffice"], ["word", "excel", "powerpoint", "docx", "xlsx", "convertir a pdf", "oficina"]),

        // Internet y descargas
        T("cURL.cURL", "curl", "Descarga archivos y prueba páginas y APIs.", ToolCategory.Web, "",
            ["curl"], ["descargar", "api", "http", "web", "peticion"]),
        T("JernejSimoncic.Wget", "Wget", "Descarga archivos y sitios completos, y retoma descargas cortadas.", ToolCategory.Web, "",
            ["wget"], ["descargar", "bajar archivo", "sitio completo", "reanudar descarga"]),
        T("aria2.aria2", "aria2", "Descarga rápido con varias conexiones a la vez, y torrents.", ToolCategory.Web, "",
            ["aria2c"], ["descargar", "acelerar descarga", "torrent", "magnet"]),
        T("Rclone.Rclone", "rclone", "Copia y sincroniza archivos con Google Drive, OneDrive, Dropbox y otros.", ToolCategory.Web, "",
            ["rclone"], ["nube", "google drive", "onedrive", "dropbox", "sincronizar", "respaldo"]),
        T("Ookla.Speedtest.CLI", "Speedtest", "Mide la velocidad de tu conexión a internet.", ToolCategory.Web, "",
            ["speedtest"], ["velocidad", "internet", "conexion", "wifi", "lento"]),
        T("httpie.httpie", "HTTPie", "Prueba APIs con comandos fáciles de leer.", ToolCategory.Web, "",
            ["http", "https"], ["api", "http", "json", "rest", "peticion"]),

        // Programación
        T("Git.Git", "Git", "Guarda el historial de tus proyectos y colabora con otras personas.", ToolCategory.Developer, "",
            ["git"], ["versiones", "historial", "repositorio", "commit", "github", "clonar"]),
        T("GitHub.cli", "GitHub CLI", "Trabaja con GitHub desde la terminal: repositorios, PR e issues.", ToolCategory.Developer, "",
            ["gh"], ["github", "pull request", "issue", "repositorio", "publicar"]),
        T("OpenJS.NodeJS.LTS", "Node.js", "Ejecuta JavaScript y trae npm para instalar paquetes.", ToolCategory.Developer, "",
            ["node", "npm", "npx"], ["javascript", "npm", "node", "web", "react", "paquetes"]),
        T("CoreyButler.NVMforWindows", "nvm para Windows", "Instala varias versiones de Node y cambia entre ellas.", ToolCategory.Developer, "",
            ["nvm"], ["node", "versiones de node", "cambiar node"]),
        T("Python.Python.3.13", "Python", "El lenguaje de programación más usado para scripts y datos.", ToolCategory.Developer, "",
            ["python", "py", "pip"], ["python", "script", "pip", "datos", "programar"]),
        T("astral-sh.uv", "uv", "Instala Python, paquetes y herramientas de Python muy rápido.", ToolCategory.Developer, "",
            ["uv", "uvx"], ["python", "pip", "entorno virtual", "paquetes python", "herramientas python"]),
        new CatalogTool("pipx", "pipx", "Instala programas hechos en Python sin mezclar sus dependencias.", ToolCategory.Developer, "",
            ["pipx"], ["python", "herramientas python", "instalar programa python"])
        {
            Manager = PackageManager.Pipx,
            CustomInstallCommand = "py -m pip install --user pipx; py -m pipx ensurepath",
        },
        T("Microsoft.PowerShell", "PowerShell 7", "La versión moderna de PowerShell: más rápida y con más comandos.", ToolCategory.Developer, "",
            ["pwsh"], ["powershell", "terminal", "shell", "scripts"]),
        T("Microsoft.VisualStudioCode", "Visual Studio Code", "Editor de código con extensiones para cualquier lenguaje.", ToolCategory.Developer, "",
            ["code"], ["editor", "codigo", "programar", "vscode"]),
        T("Docker.DockerDesktop", "Docker Desktop", "Ejecuta aplicaciones en contenedores aislados.", ToolCategory.Developer, "",
            ["docker"], ["contenedor", "contenedores", "imagen docker", "servidor", "compose"]),
        T("GoLang.Go", "Go", "Lenguaje de Google para programas rápidos y simples de distribuir.", ToolCategory.Developer, "",
            ["go"], ["go", "golang", "programar"]),
        T("Rustlang.Rustup", "Rust", "Instala Rust y cargo para compilar programas en Rust.", ToolCategory.Developer, "",
            ["rustup", "cargo", "rustc"], ["rust", "cargo", "compilar"]),
        T("Microsoft.DotNet.SDK.10", ".NET SDK", "Compila y ejecuta programas en C# y .NET.", ToolCategory.Developer, "",
            ["dotnet"], ["c#", "csharp", ".net", "dotnet", "compilar"]),
        T("SQLite.SQLite", "SQLite", "Abre y consulta bases de datos SQLite.", ToolCategory.Developer, "",
            ["sqlite3"], ["base de datos", "sql", "consulta", "db"]),
        T("jqlang.jq", "jq", "Filtra y da formato a datos JSON.", ToolCategory.Developer, "",
            ["jq"], ["json", "filtrar", "formatear json", "api"]),

        // Archivos y sistema
        T("7zip.7zip", "7-Zip", "Comprime y descomprime zip, 7z, rar y muchos formatos más.", ToolCategory.Files, "",
            ["7z"], ["zip", "rar", "7z", "comprimir", "descomprimir", "extraer", "tar"],
            "7z x archivo.rar"),
        T("BurntSushi.ripgrep.MSVC", "ripgrep", "Busca texto dentro de archivos, muy rápido.", ToolCategory.Files, "",
            ["rg"], ["buscar texto", "buscar en archivos", "grep", "contenido"],
            "rg \"texto\""),
        T("sharkdp.fd", "fd", "Busca archivos por nombre, simple y rápido.", ToolCategory.Files, "",
            ["fd"], ["buscar archivos", "encontrar", "nombre de archivo"]),
        T("sharkdp.bat", "bat", "Muestra archivos de texto con colores y números de línea.", ToolCategory.Files, "",
            ["bat"], ["ver archivo", "leer archivo", "colores", "cat"]),
        T("junegunn.fzf", "fzf", "Filtra listas al escribir: archivos, historial, lo que sea.", ToolCategory.Files, "",
            ["fzf"], ["buscar", "filtrar", "historial", "elegir"]),
        T("eza-community.eza", "eza", "Lista archivos con colores, íconos y vista de árbol.", ToolCategory.Files, "",
            ["eza"], ["listar", "archivos", "arbol", "carpetas", "ls"]),
        T("dundee.gdu", "gdu", "Muestra qué carpetas ocupan más espacio en el disco.", ToolCategory.Files, "",
            ["gdu"], ["espacio", "disco lleno", "que ocupa", "tamano", "carpetas grandes"]),
        T("Microsoft.Sysinternals.Suite", "Sysinternals", "Herramientas de Microsoft para ver procesos, archivos abiertos y más.", ToolCategory.Files, "",
            ["procexp", "handle", "du"], ["procesos", "archivo en uso", "sistema", "diagnostico"]),
        T("Microsoft.WindowsTerminal", "Terminal Windows", "La terminal moderna de Windows, con pestañas.", ToolCategory.Files, "",
            ["wt"], ["terminal", "pestanas", "consola"]),
        T("Microsoft.PowerToys", "PowerToys", "Utilidades de Microsoft: renombrar en lote, selector de color y más.", ToolCategory.Files, "",
            ["PowerToys"], ["renombrar en lote", "utilidades", "selector de color", "atajos"]),
    ];

    /// <summary>Tools that match what someone wants to do, best first.</summary>
    public static List<CatalogTool> Search(string query)
    {
        var words = Normalize(query).Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0) return All.ToList();
        var normalizedQuery = string.Join(' ', words);
        return All
            .Select(tool => (Tool: tool, Score: Score(tool, normalizedQuery, words)))
            .Where(match => match.Score > 0)
            .OrderByDescending(match => match.Score)
            .ThenBy(match => match.Tool.Title, StringComparer.CurrentCultureIgnoreCase)
            .Select(match => match.Tool)
            .ToList();
    }

    /// <summary>The tool that provides a command (<c>ffmpeg</c>, <c>rg</c>), if it's in the catalog.</summary>
    public static CatalogTool? ProvidingCommand(string command) =>
        All.FirstOrDefault(tool => tool.Commands.Any(c => c.Equals(command, StringComparison.OrdinalIgnoreCase)));

    public static CatalogTool? WithId(string id) =>
        All.FirstOrDefault(tool => tool.Id.Equals(id, StringComparison.OrdinalIgnoreCase));

    private static int Score(CatalogTool tool, string query, string[] words)
    {
        var score = 0;
        if (Normalize(tool.Title) == query || tool.Commands.Any(c => Normalize(c) == query)) score += 100;
        foreach (var keyword in tool.Keywords)
        {
            if (query.Contains(keyword)) score += 10 + keyword.Length;
        }
        var haystack = Normalize($"{tool.Title} {tool.Detail} {string.Join(' ', tool.Commands)} {tool.Id}");
        foreach (var word in words)
        {
            if (word.Length >= 3 && haystack.Contains(word)) score += 3;
            if (tool.Keywords.Any(k => k.Split(' ').Contains(word))) score += 5;
        }
        return score;
    }

    /// <summary>Lowercase, without accents or punctuation.</summary>
    internal static string Normalize(string text)
    {
        var builder = new StringBuilder(text.Length);
        foreach (var character in text.Normalize(NormalizationForm.FormD))
        {
            var category = CharUnicodeInfo.GetUnicodeCategory(character);
            if (category == UnicodeCategory.NonSpacingMark) continue;
            builder.Append(char.IsLetterOrDigit(character) || character is '#' or '.' or '-' ? char.ToLowerInvariant(character) : ' ');
        }
        return builder.ToString();
    }
}
