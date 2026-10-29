namespace Comando.Core.Language;

/// <summary>
/// Tells a mistyped command (“gti status”) from a request in plain words, so
/// it runs and gets a “did you mean” hint instead of going to the assistant.
/// </summary>
public static class TypoDetector
{
    private static readonly Dictionary<string, string[]> Subcommands = new(StringComparer.OrdinalIgnoreCase)
    {
        ["git"] = ["status", "add", "commit", "push", "pull", "log", "diff", "clone", "checkout", "branch", "merge", "rebase", "stash", "init", "fetch", "switch", "restore", "reset", "remote", "tag", "show"],
        ["npm"] = ["install", "i", "run", "start", "test", "init", "update", "uninstall", "ci", "publish", "outdated", "ls"],
        ["npx"] = ["create-react-app", "serve", "vite", "tsc"],
        ["winget"] = ["install", "upgrade", "search", "list", "uninstall", "show"],
        ["docker"] = ["run", "ps", "build", "pull", "images", "compose", "exec", "stop", "start", "logs"],
        ["pip"] = ["install", "uninstall", "list", "freeze", "show"],
        ["dotnet"] = ["build", "run", "test", "new", "restore", "publish", "add"],
        ["cargo"] = ["build", "run", "test", "new", "add", "check"],
        ["yarn"] = ["add", "install", "run", "build", "dev", "start"],
        ["pnpm"] = ["add", "install", "run", "dev", "build", "start"],
        ["kubectl"] = ["get", "apply", "describe", "logs", "delete"],
        ["gh"] = ["pr", "repo", "issue", "auth", "run", "release"],
        ["scoop"] = ["install", "update", "search", "list", "uninstall", "status"],
    };

    /// <summary>
    /// True when the first word is one or two letters off a common tool and
    /// the second is one of its subcommands or an option.
    /// </summary>
    public static bool IsMistypedCommand(string text)
    {
        var words = text.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length < 2) return false;
        var first = words[0].ToLowerInvariant();
        var second = words[1];
        foreach (var (tool, subcommands) in Subcommands)
        {
            var distance = ErrorExplainer.EditDistance(first, tool);
            if (distance is > 0 and <= 2 && first.Length >= 2
                && (second.StartsWith('-') || subcommands.Contains(second, StringComparer.OrdinalIgnoreCase)))
            {
                return true;
            }
        }
        return false;
    }
}
