using System.Text.RegularExpressions;

namespace Comando.Core.Assistant;

/// <summary>
/// Tells a command (“git status”, “Get-ChildItem”) from a request in plain
/// words (“sube esto a GitHub”).
/// </summary>
public static partial class IntentDetector
{
    /// <summary>Words PowerShell and cmd understand on their own, whatever is installed.</summary>
    private static readonly HashSet<string> Builtins = new(StringComparer.OrdinalIgnoreCase)
    {
        "cd", "dir", "ls", "cls", "clear", "echo", "exit", "set", "type", "copy", "cp", "move", "mv", "del", "rm", "ren",
        "md", "mkdir", "rd", "rmdir", "start", "where", "cat", "pwd", "help", "man", "history", "kill", "ps", "sleep",
        "foreach", "if", "while", "for", "function", "param", "return", "try", "switch", "explorer", "notepad", "ipconfig",
        "ping", "tracert", "netstat", "tasklist", "taskkill", "whoami", "hostname", "systeminfo", "shutdown", "papelera",
    };

    /// <summary>Approved PowerShell verbs: <c>Get-</c>, <c>Set-</c>, <c>New-</c>…</summary>
    private static readonly HashSet<string> Verbs = new(StringComparer.OrdinalIgnoreCase)
    {
        "add", "clear", "close", "copy", "enter", "exit", "find", "format", "get", "hide", "join", "lock", "move", "new", "open",
        "optimize", "pop", "push", "redo", "remove", "rename", "reset", "resize", "search", "select", "set", "show", "skip",
        "split", "step", "switch", "undo", "unlock", "watch", "connect", "disconnect", "read", "receive", "send", "write",
        "backup", "checkpoint", "compare", "compress", "convert", "convertfrom", "convertto", "dismount", "edit", "expand",
        "export", "group", "import", "initialize", "limit", "merge", "mount", "out", "publish", "restore", "save", "sync",
        "unpublish", "update", "approve", "assert", "build", "complete", "confirm", "deny", "deploy", "disable", "enable",
        "install", "invoke", "register", "request", "restart", "resume", "start", "stop", "submit", "suspend", "uninstall",
        "unregister", "wait", "debug", "measure", "ping", "repair", "resolve", "test", "trace", "block", "grant", "protect",
        "revoke", "unblock", "unprotect", "use", "where", "foreach", "sort", "tee",
    };

    public static bool IsPlainLanguage(string text, IReadOnlySet<string> knownCommands)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0 || trimmed.Contains('\n')) return false;
        // “?” forces the assistant, for requests that start with a command name.
        if (trimmed.StartsWith('?')) return true;

        var words = trimmed.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var first = words[0];
        var program = first.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? first[..^4] : first;
        var known = knownCommands.Contains(program) || knownCommands.Contains(program.ToLowerInvariant()) || Builtins.Contains(program);
        if (words.Length == 1)
        {
            // “Hola”, “gracias” or “ayuda” on their own, unless a program has that name.
            if (known || IsCmdlet(program)) return false;
            return TextNormalizer.IsGreeting(trimmed) || TextNormalizer.IsThanks(trimmed) || AppGuide.TopicFor(trimmed) is not null;
        }
        if (first.IndexOfAny(['\\', '/', '=', '$', '&']) >= 0 || first.StartsWith('.') || first.StartsWith('~') || first.StartsWith('['))
        {
            return false;
        }
        if (known || IsCmdlet(program)) return false;
        // Shell syntax means a command, even with an unknown program.
        string[] syntax = ["|", ">", "&&", ";", " -", "$(", "`", "{", "@("];
        if (syntax.Any(trimmed.Contains)) return false;
        return true;
    }

    /// <summary>The request without a leading “?”.</summary>
    public static string Request(string text)
    {
        var trimmed = text.Trim();
        return trimmed.StartsWith('?') ? trimmed[1..].Trim() : trimmed;
    }

    /// <summary><c>Get-ChildItem</c>, <c>ConvertTo-Json</c>: an approved verb, a dash and a noun.</summary>
    public static bool IsCmdlet(string word)
    {
        var match = CmdletPattern().Match(word);
        return match.Success && Verbs.Contains(match.Groups[1].Value);
    }

    [GeneratedRegex(@"^([A-Za-z]+)-[A-Za-z][A-Za-z0-9]*$")]
    private static partial Regex CmdletPattern();
}
