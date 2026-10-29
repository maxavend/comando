using System.Text;

namespace Comando.Core.Language;

/// <summary>Splits a PowerShell command line into words, the way people read it.</summary>
public static class ShellWords
{
    /// <summary>
    /// <c>Remove-Item "my file.txt" -Force</c> → <c>Remove-Item</c>, <c>my file.txt</c>, <c>-Force</c>.
    /// Quotes group words and are removed; a backtick escapes the next character.
    /// </summary>
    public static List<string> Split(string line)
    {
        var words = new List<string>();
        var current = new StringBuilder();
        var inWord = false;
        char? quote = null;
        for (var i = 0; i < line.Length; i++)
        {
            var character = line[i];
            if (character == '`' && quote != '\'' && i + 1 < line.Length)
            {
                current.Append(line[++i]);
                inWord = true;
            }
            else if (quote is { } open)
            {
                if (character == open) quote = null;
                else current.Append(character);
            }
            else if (character is '"' or '\'')
            {
                quote = character;
                inWord = true;
            }
            else if (char.IsWhiteSpace(character))
            {
                if (inWord) words.Add(current.ToString());
                current.Clear();
                inWord = false;
            }
            else
            {
                current.Append(character);
                inWord = true;
            }
        }
        if (inWord) words.Add(current.ToString());
        return words;
    }

    /// <summary>The program a word names, lowercased: <c>C:\Git\usr\bin\rm.exe</c> → <c>rm</c>.</summary>
    public static string ProgramName(string word)
    {
        var name = word.TrimStart('&', '.', ' ').Split('/', '\\')[^1].ToLowerInvariant();
        return name.EndsWith(".exe") ? name[..^4] : name;
    }

    /// <summary>Quotes a path for PowerShell when it needs it.</summary>
    public static string Quote(string word) =>
        word.Length > 0 && word.All(c => char.IsLetterOrDigit(c) || c is '.' or '_' or '-' or '\\' or '/' or ':' or '*' or '?')
            ? word
            : "'" + word.Replace("'", "''") + "'";
}

/// <summary>
/// Turns a delete into the equivalent <c>papelera</c> (defined by the shell
/// integration), so files go to the Recycle Bin and can be recovered.
/// </summary>
public static class RecycleBinConverter
{
    private static readonly HashSet<string> DeleteCommands = ["remove-item", "ri", "rm", "del", "erase", "rd", "rmdir"];

    /// <summary><c>Remove-Item -Recurse a "b c"</c> → <c>papelera a 'b c'</c>. Null if it isn't a plain delete.</summary>
    public static string? Command(string command)
    {
        // Pipes, redirects or chains change the meaning; leave those alone.
        if (command.IndexOfAny(['|', ';', '>', '<', '&']) >= 0) return null;
        var words = ShellWords.Split(command.Trim());
        if (words.Count < 2 || !DeleteCommands.Contains(ShellWords.ProgramName(words[0]))) return null;
        var paths = new List<string>();
        var endOfOptions = false;
        for (var i = 1; i < words.Count; i++)
        {
            var word = words[i];
            if (!endOfOptions && word == "--") { endOfOptions = true; continue; }
            if (!endOfOptions && word.StartsWith('/') && word.Length == 2) continue; // cmd: /s /q /f
            if (!endOfOptions && word.StartsWith('-'))
            {
                // -Path and -LiteralPath take the next word as a path.
                if (word.Equals("-Path", StringComparison.OrdinalIgnoreCase) || word.Equals("-LiteralPath", StringComparison.OrdinalIgnoreCase)) continue;
                // Other parameters with a value: -Filter *.tmp, -Include, -Exclude.
                if (word.Equals("-Filter", StringComparison.OrdinalIgnoreCase)
                    || word.Equals("-Include", StringComparison.OrdinalIgnoreCase)
                    || word.Equals("-Exclude", StringComparison.OrdinalIgnoreCase))
                {
                    return null;
                }
                continue;
            }
            paths.Add(word);
        }
        return paths.Count == 0 ? null : "papelera " + string.Join(' ', paths.Select(ShellWords.Quote));
    }
}
