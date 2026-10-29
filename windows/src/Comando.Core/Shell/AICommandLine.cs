namespace Comando.Core.Shell;

/// <summary>
/// Command-line AI agents (agy, Claude Code, Gemini CLI, Codex…). They draw
/// their own screen, but they are conversations: while one runs, the chat's
/// field keeps working and sends each message to it.
/// </summary>
public static class AICommandLine
{
    public static readonly IReadOnlySet<string> Commands = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "agy", "claude", "gemini", "codex", "qwen", "aider", "opencode", "cursor-agent", "copilot",
        "goose", "amp", "crush", "droid", "kiro", "kiro-cli", "kimi", "cline", "auggie", "q", "ollama", "llm",
    };

    /// <summary>
    /// Whether the command starts one of them (<c>agy</c>, <c>npx @openai/codex</c>,
    /// <c>ollama run llama3</c>…).
    /// </summary>
    public static bool IsAgent(string command)
    {
        var words = command.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length == 0) return false;
        var first = ShellSession.FirstWord(words[0]);
        if (first is "npx" or "bunx" or "pnpx" && words.Skip(1).FirstOrDefault(w => !w.StartsWith('-')) is { } package)
        {
            var name = package.Split('/')[^1];
            return Commands.Contains(name) || name.EndsWith("-cli") && Commands.Contains(name[..^4]);
        }
        if (first == "ollama") return words.ElementAtOrDefault(1) == "run";
        if (first == "q") return words.ElementAtOrDefault(1) == "chat";
        return Commands.Contains(first);
    }
}
