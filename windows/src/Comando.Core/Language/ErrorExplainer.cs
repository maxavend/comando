using System.Text.RegularExpressions;
using Comando.Core.Shell;

namespace Comando.Core.Language;

/// <summary>A plain-language explanation of a failed command, with an optional command to try.</summary>
public sealed record CommandHint(string Message, string? Suggestion = null);

/// <summary>Explains the errors people hit most often on Windows, in plain language.</summary>
public static partial class ErrorExplainer
{
    /// <summary>Exit code of a program stopped with Ctrl+C in a Windows console (STATUS_CONTROL_C_EXIT).</summary>
    public const int InterruptedStatus = -1073741510;

    /// <summary>Commands from macOS and Linux that people type on Windows, and what does the same here.</summary>
    private static readonly Dictionary<string, string> WindowsEquivalents = new(StringComparer.OrdinalIgnoreCase)
    {
        ["open"] = "Invoke-Item",
        ["touch"] = "New-Item",
        ["grep"] = "Select-String",
        ["which"] = "Get-Command",
        ["pbcopy"] = "Set-Clipboard",
        ["pbpaste"] = "Get-Clipboard",
        ["brew"] = "winget",
        ["apt"] = "winget",
        ["apt-get"] = "winget",
        ["ifconfig"] = "ipconfig",
        ["killall"] = "Stop-Process -Name",
        ["df"] = "Get-PSDrive",
        ["uname"] = "Get-ComputerInfo",
        ["head"] = "Get-Content -TotalCount 10",
        ["tail"] = "Get-Content -Tail 10",
        ["nano"] = "notepad",
        ["python3"] = "python",
    };

    public static CommandHint? Hint(string command, string output, int? exitCode, Func<IEnumerable<string>> knownCommands)
    {
        if (exitCode is not { } code || code == 0 || code == InterruptedStatus) return null;
        var text = output.ToLowerInvariant();
        var name = ShellSession.FirstWord(command);

        if (IsNotFound(text))
        {
            if (WindowsEquivalents.TryGetValue(name, out var equivalent))
            {
                return new CommandHint(
                    $"“{name}” no existe en Windows. Aquí se usa “{equivalent}”.",
                    ReplacingFirstWord(command, equivalent));
            }
            if (name.Equals("sudo", StringComparison.OrdinalIgnoreCase))
            {
                return new CommandHint("Windows no tiene sudo. Si de verdad necesitas permisos de administrador, abre Comando como administrador.");
            }
            if (ClosestCommand(name, knownCommands()) is { } match)
            {
                return new CommandHint(
                    $"No existe el comando “{name}”. ¿Quisiste decir “{match}”?",
                    ReplacingFirstWord(command, match));
            }
            return new CommandHint($"No existe el comando “{name}”. Revisa cómo está escrito o si está instalado.");
        }
        if (ContainsAny(text, "running scripts is disabled", "la ejecución de scripts está deshabilitada", "ejecucion de scripts esta deshabilitada", "pssecurityexception"))
        {
            return new CommandHint(
                "Windows no deja ejecutar scripts en este equipo. Puedes permitir los tuyos y los firmados solo para tu usuario.",
                "Set-ExecutionPolicy -Scope CurrentUser RemoteSigned");
        }
        if (ContainsAny(text, "parsererror", "unexpected token", "token inesperado", "missing closing", "missing terminator", "falta el terminador", "falta el carácter de cierre", "the string is missing the terminator"))
        {
            return new CommandHint("El comando tiene un error de escritura, como comillas, llaves o paréntesis sin cerrar.");
        }
        if (ContainsAny(text, "being used by another process", "está siendo utilizado por otro proceso", "esta siendo utilizado por otro proceso", "ebusy"))
        {
            return new CommandHint("Otro programa tiene abierto ese archivo. Ciérralo y vuelve a intentarlo.");
        }
        if (ContainsAny(text, "eaddrinuse", "address already in use", "only one usage of each socket address", "solo se permite un uso de cada dirección de socket"))
        {
            var port = PortPattern().Match(output);
            return new CommandHint(
                "Ese puerto ya lo usa otro programa, quizá un servidor que dejaste abierto.",
                port.Success ? $"Get-NetTCPConnection -LocalPort {port.Groups[1].Value} -State Listen | ForEach-Object {{ Get-Process -Id $_.OwningProcess }}" : null);
        }
        if (ContainsAny(text, "unauthorizedaccessexception", "access is denied", "access to the path", "acceso denegado", "se denegó el acceso", "permission denied", "eacces", "eperm"))
        {
            return new CommandHint("No tienes permiso para hacer esto. Puede que el archivo sea de otro usuario, esté protegido o haga falta abrir Comando como administrador.");
        }
        if (text.Contains("enoent") && text.Contains("package.json"))
        {
            return new CommandHint("Esta carpeta no tiene un package.json: no es un proyecto de Node, o estás en otra carpeta.");
        }
        if (ContainsAny(text, "itemnotfoundexception", "cannot find path", "no se encuentra la ruta", "no se puede encontrar la ruta", "no such file or directory", "enoent", "the system cannot find the path", "el sistema no puede encontrar"))
        {
            return new CommandHint("No se encontró ese archivo o carpeta. Revisa el nombre; Tab te ayuda a completarlo.");
        }
        if (text.Contains("not a git repository"))
        {
            return new CommandHint("Esta carpeta no es un repositorio de Git.");
        }
        if (text.Contains("please tell me who you are") || text.Contains("author identity unknown"))
        {
            return new CommandHint(
                "Git necesita saber tu nombre y correo para guardar cambios. Configúralos una vez y listo.",
                "git config --global user.name \"Tu nombre\"; git config --global user.email \"tu@correo.com\"");
        }
        if (text.Contains("failed to push some refs") && (text.Contains("fetch first") || text.Contains("non-fast-forward") || text.Contains("rejected")))
        {
            return new CommandHint("El repositorio remoto tiene cambios que tú no tienes. Tráelos primero y vuelve a subir.", "git pull");
        }
        if (text.Contains("conflict (") || text.Contains("merge conflict") || text.Contains("fix conflicts"))
        {
            return new CommandHint("Hay conflictos: dos cambios tocaron las mismas líneas. Revisa los archivos marcados y elige qué queda.");
        }
        if (ContainsAny(text, "could not resolve host", "unknown host", "no such host is known", "no se conoce este host", "no se puede resolver", "getaddrinfo enotfound"))
        {
            return new CommandHint("No se pudo llegar a esa dirección. Revisa tu conexión o el nombre.");
        }
        return null;
    }

    private static bool IsNotFound(string text) => ContainsAny(text,
        "is not recognized as a name of a cmdlet",
        "is not recognized as the name of a cmdlet",
        "is not recognized as an internal or external command",
        "no se reconoce como nombre de un cmdlet",
        "no se reconoce el término",
        "no se reconoce el termino",
        "no se reconoce como un comando interno o externo",
        "commandnotfoundexception",
        "command not found");

    private static bool ContainsAny(string text, params string[] phrases) => phrases.Any(text.Contains);

    /// <summary>The known command closest to <paramref name="name"/>, if it is a plausible typo.</summary>
    public static string? ClosestCommand(string name, IEnumerable<string> commands)
    {
        if (name.Length < 2) return null;
        var limit = name.Length <= 3 ? 1 : 2;
        string? bestName = null;
        var bestDistance = int.MaxValue;
        foreach (var candidate in commands)
        {
            if (Math.Abs(candidate.Length - name.Length) > limit || candidate.Equals(name, StringComparison.OrdinalIgnoreCase)) continue;
            var distance = EditDistance(name.ToLowerInvariant(), candidate.ToLowerInvariant());
            if (distance > limit) continue;
            if (bestName is not null && (distance > bestDistance || (distance == bestDistance && string.CompareOrdinal(candidate, bestName) >= 0))) continue;
            bestName = candidate;
            bestDistance = distance;
        }
        return bestName;
    }

    /// <summary>Optimal string alignment distance: edits plus adjacent swaps (“gti” → “git”).</summary>
    public static int EditDistance(string a, string b)
    {
        if (a.Length == 0) return b.Length;
        if (b.Length == 0) return a.Length;
        var d = new int[a.Length + 1, b.Length + 1];
        for (var i = 0; i <= a.Length; i++) d[i, 0] = i;
        for (var j = 0; j <= b.Length; j++) d[0, j] = j;
        for (var i = 1; i <= a.Length; i++)
        {
            for (var j = 1; j <= b.Length; j++)
            {
                var cost = a[i - 1] == b[j - 1] ? 0 : 1;
                d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1])
                {
                    d[i, j] = Math.Min(d[i, j], d[i - 2, j - 2] + 1);
                }
            }
        }
        return d[a.Length, b.Length];
    }

    private static string ReplacingFirstWord(string command, string word)
    {
        var trimmed = command.TrimStart(' ');
        var space = trimmed.IndexOf(' ');
        return space < 0 ? word : word + trimmed[space..];
    }

    [GeneratedRegex(@"(?:port|puerto|:)\s*(\d{2,5})\b", RegexOptions.IgnoreCase)]
    private static partial Regex PortPattern();
}
