using System.Text;

namespace Comando.Core.Language;

/// <summary>One piece of a command line and what it means.</summary>
public sealed record CommandPart(int Id, string Token, string Explanation);

/// <summary>Explains a PowerShell command piece by piece: the program, its options and its arguments.</summary>
public static class CommandExplainer
{
    public static IReadOnlyList<CommandPart> Parts(string command)
    {
        var parts = new List<CommandPart>();
        string? program = null;
        string? subcommand = null;
        var expectsValue = false;
        foreach (var token in Tokens(command))
        {
            string explanation;
            if (Connectors.TryGetValue(token, out var connector))
            {
                explanation = connector;
                program = null;
                subcommand = null;
                expectsValue = false;
            }
            else if (program is null)
            {
                if (token.StartsWith('$'))
                {
                    explanation = token == "$_" ? "El elemento actual" : "Una variable";
                }
                else if (token is "&" or ".")
                {
                    explanation = "Ejecuta el script o programa que sigue";
                }
                else
                {
                    program = CommandGlossary.Canonical(token);
                    explanation = CommandGlossary.Describe(token) ?? "El programa que se ejecuta";
                }
            }
            else if (token == "=")
            {
                explanation = "Guarda lo que sigue";
            }
            else if (token.StartsWith('-') && token.Length > 1 && !char.IsDigit(token[1]))
            {
                explanation = DescribeOption(token, program, subcommand);
                // Parameters like -Path take the next word as their value; switches like -Recurse don't.
                expectsValue = ValueParameters.Contains(token);
            }
            else if (subcommand is null && CommandGlossary.HasSubcommands(program))
            {
                subcommand = token;
                explanation = CommandGlossary.Describe($"{program} {token}") ?? "La acción del programa";
            }
            else
            {
                explanation = expectsValue ? "El valor de la opción anterior" : DescribeArgument(token);
                expectsValue = false;
            }
            parts.Add(new CommandPart(parts.Count, token, explanation));
        }
        return parts;
    }

    /// <summary>
    /// Splits into words, keeping quotes and treating <c>|</c>, <c>&gt;</c>,
    /// <c>&amp;&amp;</c> and <c>;</c> as tokens. A backtick escapes the next character;
    /// backslashes are part of Windows paths.
    /// </summary>
    public static List<string> Tokens(string command)
    {
        var result = new List<string>();
        var current = new StringBuilder();
        char? quote = null;
        void Flush()
        {
            if (current.Length > 0) result.Add(current.ToString());
            current.Clear();
        }
        for (var i = 0; i < command.Length; i++)
        {
            var character = command[i];
            if (quote is { } open)
            {
                current.Append(character);
                if (character == open) quote = null;
                continue;
            }
            switch (character)
            {
                case '\'' or '"':
                    quote = character;
                    current.Append(character);
                    break;
                case ' ' or '\t' or '\n':
                    Flush();
                    break;
                case '|' or ';' or '>' or '<' or '&':
                    // & on its own at the start is the call operator; inside a word (a URL) it stays.
                    if (character == '&' && current.Length > 0 && (i + 1 >= command.Length || command[i + 1] != '&'))
                    {
                        current.Append(character);
                        break;
                    }
                    Flush();
                    var symbol = character.ToString();
                    if (i + 1 < command.Length)
                    {
                        var next = command[i + 1];
                        if ((next == character && character != ';') || (character == '>' && next == '&'))
                        {
                            symbol += next;
                            i++;
                        }
                    }
                    result.Add(symbol);
                    break;
                case '`':
                    current.Append(character);
                    if (i + 1 < command.Length)
                    {
                        current.Append(command[i + 1]);
                        i++;
                    }
                    break;
                default:
                    current.Append(character);
                    break;
            }
        }
        Flush();
        return result;
    }

    private static readonly HashSet<string> ValueParameters = new(StringComparer.OrdinalIgnoreCase)
    {
        "-Path", "-LiteralPath", "-Filter", "-Include", "-Exclude", "-Destination", "-DestinationPath", "-NewName", "-Name",
        "-ItemType", "-Pattern", "-First", "-Last", "-Skip", "-Tail", "-TotalCount", "-Count", "-Uri", "-OutFile", "-Method",
        "-Property", "-ExpandProperty", "-Id", "-Depth", "-Value", "-Encoding", "-Scope", "-ExecutionPolicy", "-LocalPort",
        "-State", "-AddressFamily", "-Source", "--id", "--source", "-m",
    };

    private static readonly Dictionary<string, string> Connectors = new()
    {
        ["|"] = "Pasa el resultado al comando siguiente",
        ["||"] = "Si falla, ejecuta lo que sigue",
        ["&&"] = "Si funciona, ejecuta lo que sigue",
        [";"] = "Después, ejecuta lo que sigue",
        [">"] = "Guarda el resultado en un archivo (lo reemplaza)",
        [">>"] = "Agrega el resultado al final de un archivo",
        ["<"] = "Lee la entrada desde un archivo",
    };

    private static string DescribeArgument(string token)
    {
        if (token.StartsWith('\'') || token.StartsWith('"')) return "Un texto";
        if (token.StartsWith('{')) return "Un bloque de instrucciones";
        if (token.StartsWith('$')) return token == "$_" ? "El elemento actual" : "Una variable";
        if (token.Contains('*') || token.Contains('?')) return "Un patrón: todos los nombres que coincidan";
        if (token.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || token.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return "Una dirección web";
        if (token is "." or ".\\" or "./") return "Esta carpeta";
        if (token is ".." or "..\\" or "../") return "La carpeta de arriba";
        if (token == "~") return "Tu carpeta personal";
        if (token.All(char.IsDigit)) return "Un número";
        if (token.Contains('\\') || token.Contains('/') || token.Contains('.') || token.StartsWith('~') || (token.Length >= 2 && token[1] == ':')) return "Un archivo o carpeta";
        return "Un dato para el comando";
    }

    private static string DescribeOption(string token, string program, string? subcommand)
    {
        var key = subcommand is null ? program : $"{program} {subcommand.ToLowerInvariant()}";
        var table = Options.GetValueOrDefault(key) ?? Options.GetValueOrDefault(program);
        if (table is not null)
        {
            if (table.TryGetValue(token, out var exact)) return exact;
            // PowerShell accepts any unambiguous prefix: -Rec for -Recurse.
            var prefixed = table.Keys.Where(name => name.Length > 2 && name.StartsWith(token, StringComparison.OrdinalIgnoreCase)).ToList();
            if (token.Length > 2 && prefixed.Count == 1) return table[prefixed[0]];
            // Combined short flags: -fd → -f, -d.
            if (!token.StartsWith("--") && token.Length > 2 && token.Skip(1).All(char.IsLower))
            {
                var letters = token.Skip(1).Select(letter => $"-{letter}").ToList();
                var described = letters.Where(table.ContainsKey).Select(flag => $"{flag}: {table[flag]}").ToList();
                if (described.Count == letters.Count) return string.Join(" · ", described);
            }
        }
        return "Una opción que cambia cómo funciona";
    }

    private static Dictionary<string, string> Table(params (string Option, string Meaning)[] entries)
    {
        var table = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (option, meaning) in entries) table[option] = meaning;
        return table;
    }

    /// <summary>Case-sensitive tables for tools with Unix-style flags, where -f and -F differ.</summary>
    private static Dictionary<string, string> Exact(params (string Option, string Meaning)[] entries)
    {
        var table = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (option, meaning) in entries) table[option] = meaning;
        return table;
    }

    private static readonly Dictionary<string, Dictionary<string, string>> Options = new(StringComparer.OrdinalIgnoreCase)
    {
        ["get-childitem"] = Table(("-Recurse", "incluye subcarpetas"), ("-Force", "incluye ocultos y del sistema"), ("-Filter", "solo los nombres que coincidan"),
            ("-File", "solo archivos"), ("-Directory", "solo carpetas"), ("-Path", "dónde mirar"), ("-Depth", "hasta cierta profundidad"), ("-Name", "solo los nombres")),
        ["remove-item"] = Table(("-Recurse", "incluye carpetas y su contenido"), ("-Force", "también ocultos y de solo lectura, sin preguntar"),
            ("-Path", "qué borrar"), ("-LiteralPath", "qué borrar, tal cual se escribe"), ("-WhatIf", "solo muestra lo que borraría"), ("-Confirm", "pregunta antes de cada uno")),
        ["copy-item"] = Table(("-Recurse", "incluye carpetas"), ("-Force", "reemplaza sin preguntar"), ("-Destination", "a dónde copiar"), ("-Path", "qué copiar")),
        ["move-item"] = Table(("-Force", "reemplaza sin preguntar"), ("-Destination", "a dónde mover"), ("-Path", "qué mover")),
        ["rename-item"] = Table(("-NewName", "el nombre nuevo"), ("-Path", "qué renombrar")),
        ["new-item"] = Table(("-ItemType", "qué crear (File o Directory)"), ("-Name", "el nombre"), ("-Path", "dónde crearlo"), ("-Force", "también las carpetas intermedias")),
        ["get-content"] = Table(("-Tail", "las últimas líneas"), ("-TotalCount", "las primeras líneas"), ("-Wait", "sigue mostrando lo nuevo"), ("-Raw", "todo como un solo texto")),
        ["select-string"] = Table(("-Pattern", "qué buscar"), ("-Path", "en qué archivos"), ("-SimpleMatch", "busca el texto tal cual"), ("-CaseSensitive", "distingue mayúsculas"), ("-NotMatch", "las líneas que no coinciden")),
        ["select-object"] = Table(("-First", "los primeros"), ("-Last", "los últimos"), ("-Property", "qué columnas"), ("-ExpandProperty", "solo el valor de una columna"), ("-Unique", "sin repetidos")),
        ["sort-object"] = Table(("-Descending", "de mayor a menor"), ("-Property", "por qué columna"), ("-Unique", "sin repetidos")),
        ["get-process"] = Table(("-Name", "por nombre"), ("-Id", "por número de proceso")),
        ["stop-process"] = Table(("-Name", "por nombre"), ("-Id", "por número de proceso"), ("-Force", "sin dejar que guarde")),
        ["test-connection"] = Table(("-Count", "cuántos intentos")),
        ["invoke-webrequest"] = Table(("-Uri", "la dirección"), ("-OutFile", "guarda en un archivo"), ("-Method", "el tipo de consulta")),
        ["compress-archive"] = Table(("-Path", "qué comprimir"), ("-DestinationPath", "el .zip que crea"), ("-Force", "reemplaza si ya existe")),
        ["expand-archive"] = Table(("-Path", "el .zip"), ("-DestinationPath", "dónde extraer"), ("-Force", "reemplaza lo que exista")),
        ["git"] = Exact(("--version", "muestra la versión")),
        ["git log"] = Exact(("--oneline", "un commit por línea"), ("-n", "cuántos commits"), ("--graph", "con un dibujo de las ramas")),
        ["git commit"] = Exact(("-m", "con este mensaje"), ("-a", "incluye todos los cambios"), ("--amend", "corrige el último commit")),
        ["git reset"] = Exact(("--hard", "descarta los cambios"), ("--soft", "conserva los cambios")),
        ["git push"] = Exact(("--force", "reemplaza el historial remoto"), ("-f", "reemplaza el historial remoto"), ("-u", "recuerda a dónde subir")),
        ["git checkout"] = Exact(("-b", "crea una rama nueva")),
        ["git switch"] = Exact(("-c", "crea una rama nueva")),
        ["git clean"] = Exact(("-f", "sin preguntar"), ("-d", "incluye carpetas"), ("-x", "también lo ignorado")),
        ["npm install"] = Exact(("-g", "para todo el sistema"), ("-D", "solo para desarrollo"), ("--save-dev", "solo para desarrollo")),
        ["winget install"] = Table(("--id", "el identificador exacto del programa"), ("-e", "busca el nombre exacto"), ("--exact", "busca el nombre exacto"), ("--source", "de qué catálogo"), ("--silent", "sin ventanas")),
        ["winget upgrade"] = Table(("--all", "todos los que tengan versión nueva"), ("--id", "el identificador exacto del programa")),
    };
}
