using System.Text.RegularExpressions;

namespace Comando.Core.Language;

/// <summary>Why a command deserves a second look before running.</summary>
public sealed record CommandRisk(string Title, string Explanation);

/// <summary>
/// Spots commands that are hard to undo, and explains the risk in plain
/// words. Knows PowerShell's cmdlets and aliases, cmd's commands and the
/// cross-platform tools people run on Windows (git, rm from Git for Windows).
/// </summary>
public static partial class DangerDetector
{
    public static CommandRisk? Risk(string command)
    {
        var line = command.Trim();
        if (line.Length == 0) return null;

        // A script downloaded and run directly.
        if (DownloadAndRun().IsMatch(line))
        {
            return new CommandRisk(
                "Este comando descarga y ejecuta un programa de internet",
                "El programa se ejecutará sin que puedas revisarlo antes. Hazlo solo si confías en el sitio.");
        }

        // Many files renamed or moved at once: easy to get wrong, hard to undo.
        if (BatchRename().IsMatch(line))
        {
            return new CommandRisk(
                "Este comando renombra o mueve muchos archivos de una vez",
                "Revisa a qué archivos afecta antes de seguir. Si dos quedan con el mismo nombre, uno podría reemplazar al otro.");
        }

        // Each part of “a && b; c | d” runs, so each one gets checked, and so
        // do commands hidden in $(…) or script blocks.
        var segments = Separators().Split(line).Select(s => s.Trim()).Where(s => s.Length > 0).ToList();
        if (segments.Count > 1)
        {
            return segments.Select(Risk).FirstOrDefault(risk => risk is not null);
        }
        foreach (Match inner in Subexpression().Matches(line))
        {
            var body = inner.Groups[1].Success ? inner.Groups[1].Value : inner.Groups[2].Value;
            if (Risk(body) is { } risk) return risk;
        }

        var words = ShellWords.Split(line);
        if (words.Count == 0) return null;
        var name = ShellWords.ProgramName(words[0]);
        var arguments = words.Skip(1).ToList();
        bool Has(params string[] options) => arguments.Any(a => options.Any(o => a.Equals(o, StringComparison.OrdinalIgnoreCase)));
        bool HasPrefix(params string[] prefixes) => arguments.Any(a => prefixes.Any(p => a.StartsWith(p, StringComparison.OrdinalIgnoreCase)));
        // Short flags such as -rf or -fd; PowerShell parameters (-Force) are longer words.
        var unixFlags = string.Concat(arguments.Where(a => ShortFlag().IsMatch(a)).Select(a => a[1..]));

        switch (name)
        {
            case "remove-item" or "ri" or "rm" or "del" or "erase" or "rd" or "rmdir":
                var recursive = HasPrefix("-r") && !Has("-readonly") || Has("/s") || unixFlags.Contains('r') || unixFlags.Contains('R');
                var wildcard = arguments.Any(a => a.Contains('*'));
                if (recursive || wildcard)
                {
                    return new CommandRisk(
                        "Este comando borra archivos de forma permanente",
                        recursive
                            ? "Borra carpetas completas con todo su contenido. No pasa por la Papelera de reciclaje y no se puede deshacer."
                            : "Borra todos los archivos que coincidan con el patrón. No pasa por la Papelera de reciclaje y no se puede deshacer.");
                }
                break;
            case "format" or "format-volume" or "clear-disk" or "initialize-disk" or "diskpart" or "remove-partition":
                return new CommandRisk(
                    "Este comando borra un disco",
                    "Todo el contenido del disco se perderá.");
            case "git":
                var rest = string.Join(' ', arguments);
                if (rest.StartsWith("reset") && rest.Contains("--hard"))
                {
                    return new CommandRisk(
                        "Este comando descarta tus cambios",
                        "Los cambios que no guardaste con commit se perderán.");
                }
                if (rest.StartsWith("clean") && unixFlags.Contains('f'))
                {
                    return new CommandRisk(
                        "Este comando borra archivos que Git no conoce",
                        "Los archivos nuevos que no agregaste al repositorio se borrarán.");
                }
                if (rest.StartsWith("push") && (rest.Contains("--force") || unixFlags.Contains('f')))
                {
                    return new CommandRisk(
                        "Este comando reemplaza el historial remoto",
                        "Puede borrar cambios que otras personas subieron.");
                }
                break;
            case "stop-computer" or "restart-computer" or "shutdown":
                if (name == "shutdown" && Has("/a")) break;
                return new CommandRisk(
                    "Este comando apaga o reinicia el PC",
                    "Las apps abiertas se cerrarán y podrías perder trabajo sin guardar.");
            case "stop-process" or "spps" or "kill" or "taskkill":
                return new CommandRisk(
                    "Este comando cierra un programa a la fuerza",
                    "El programa no podrá guardar su trabajo antes de cerrarse.");
            case "icacls" or "takeown":
                if (Has("/t", "/r"))
                {
                    return new CommandRisk(
                        "Este comando cambia permisos de muchos archivos",
                        "Cambia todo lo que hay dentro de la carpeta. Si te equivocas, algunas apps podrían dejar de funcionar.");
                }
                break;
            case "reg" when arguments.FirstOrDefault()?.ToLowerInvariant() is "delete" or "add" or "import":
            case "remove-itemproperty" or "set-itemproperty" when HasPrefix("hklm:", "hkcu:", "registry::"):
                return new CommandRisk(
                    "Este comando cambia el Registro de Windows",
                    "Un cambio equivocado puede hacer que Windows o algunas apps dejen de funcionar.");
            case "start-process" or "saps" or "start" when Has("-verb") && arguments.Any(a => a.Equals("runas", StringComparison.OrdinalIgnoreCase)):
            case "sudo" or "gsudo":
                return new CommandRisk(
                    "Este comando se ejecuta como administrador",
                    "Tendrá acceso a todo el sistema y Windows te pedirá permiso. Úsalo solo si sabes qué hace.");
            case "set-executionpolicy":
                return new CommandRisk(
                    "Este comando cambia qué scripts puede ejecutar el PC",
                    "Una política menos estricta deja correr scripts sin firmar, incluidos los descargados de internet.");
        }
        return null;
    }

    // irm … | iex, iwr … | Invoke-Expression, curl … | sh
    [GeneratedRegex(@"(irm|iwr|invoke-restmethod|invoke-webrequest|curl|wget)\b[^|]*\|\s*(iex|invoke-expression|sh|bash|pwsh|powershell)\b|(iex|invoke-expression)\s*[\(\s]+\s*(\(?\s*(irm|iwr|invoke-restmethod|invoke-webrequest|new-object\s+net\.webclient))", RegexOptions.IgnoreCase)]
    private static partial Regex DownloadAndRun();

    // Get-ChildItem … | Rename-Item / Move-Item, foreach loops that rename, ren with wildcards
    [GeneratedRegex(@"\|\s*(%|foreach-object|foreach)?\s*\{?[^|]*\b(rename-item|ren|rni|move-item|mv|mi|move)\b|\bforeach\s*\(.+\)\s*\{[^}]*\b(rename-item|ren|rni|move-item|mv|mi|move)\b|^\s*(ren|rename)\s+\S*\*", RegexOptions.IgnoreCase)]
    private static partial Regex BatchRename();

    [GeneratedRegex(@"^-[A-Za-z]{1,4}$")]
    private static partial Regex ShortFlag();

    [GeneratedRegex(@"&&|\|\||;|\|")]
    private static partial Regex Separators();

    [GeneratedRegex(@"\$\(([^)]*)\)|\{([^}]*)\}")]
    private static partial Regex Subexpression();
}
