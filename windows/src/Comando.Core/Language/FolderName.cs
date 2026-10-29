namespace Comando.Core.Language;

/// <summary>Folder names as people see them in the File Explorer, instead of shell paths.</summary>
public static class FolderName
{
    public static string Home { get; set; } = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// <summary>“Inicio” for the home folder, the folder's own name for everything else.</summary>
    public static string Display(string path)
    {
        if (string.IsNullOrEmpty(path)) return "Inicio";
        var trimmed = path.TrimEnd('\\', '/');
        if (string.Equals(trimmed, Home.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase)) return "Inicio";
        // A drive root (C:\) has no name of its own.
        if (trimmed.Length == 2 && trimmed[1] == ':') return $"Disco {char.ToUpperInvariant(trimmed[0])}:";
        var name = trimmed.Split('\\', '/')[^1];
        return name.Length == 0 ? path : name;
    }

    /// <summary>
    /// The folder as part of a sentence: “Estás en …”. The home folder reads
    /// as “tu carpeta personal”, which says what “Inicio” means.
    /// </summary>
    public static string Phrase(string path) =>
        Display(path) == "Inicio" ? "tu carpeta personal" : Display(path);
}
