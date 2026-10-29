using System.Text.Json;

namespace Comando.Core.Agents;

/// <summary>
/// An AI agent CLI that Comando can talk to as a chat: its own words in
/// bubbles and its tools as cards, instead of the screen it draws.
/// </summary>
public enum AgentKind
{
    Agy,
    Claude,
    Qwen,
    Codex,
}

/// <summary>What the agent may do without asking, for this conversation.</summary>
public enum AgentPermission
{
    /// <summary>
    /// Headless CLIs can't ask, so anything that needs permission is denied
    /// and shown as a card with buttons.
    /// </summary>
    Ask,
    Edits,
    All,
}

/// <summary>How the CLI is driven.</summary>
public enum AgentTransport
{
    /// <summary>One process for the whole conversation, one JSON message per line.</summary>
    Persistent,
    /// <summary>A process per message that resumes the conversation by its id.</summary>
    PerTurn,
}

public static class AgentKinds
{
    public static readonly AgentKind[] All = [AgentKind.Agy, AgentKind.Claude, AgentKind.Qwen, AgentKind.Codex];

    /// <summary>The program name: <c>agy</c>, <c>claude</c>, <c>qwen</c>, <c>codex</c>.</summary>
    public static string CommandName(this AgentKind kind) => kind switch
    {
        AgentKind.Agy => "agy",
        AgentKind.Claude => "claude",
        AgentKind.Qwen => "qwen",
        _ => "codex",
    };

    /// <summary>The agent a program name names, if any (case-insensitive).</summary>
    public static AgentKind? FromName(string? name)
    {
        if (string.IsNullOrEmpty(name)) return null;
        foreach (var kind in All)
        {
            if (string.Equals(kind.CommandName(), name, StringComparison.OrdinalIgnoreCase)) return kind;
        }
        return null;
    }

    /// <summary>The agent a bare command starts (<c>agy</c>, <c>claude</c>…), if any.</summary>
    public static AgentKind? FromCommand(string command)
    {
        var words = command.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        // Only the bare name: `.\claude` is some other program.
        if (words.Length != 1 || words[0].Contains('/') || words[0].Contains('\\')) return null;
        return FromName(words[0]);
    }

    public static string DisplayName(this AgentKind kind) => kind switch
    {
        AgentKind.Agy => "Antigravity",
        AgentKind.Claude => "Claude Code",
        AgentKind.Qwen => "Qwen Code",
        _ => "Codex",
    };

    public static AgentTransport Transport(this AgentKind kind) =>
        kind is AgentKind.Agy or AgentKind.Claude ? AgentTransport.Persistent : AgentTransport.PerTurn;

    /// <summary>Whether the CLI can be given more permissions from the command line.</summary>
    public static bool HasPermissionModes(this AgentKind kind) => kind != AgentKind.Qwen;

    /// <summary>
    /// Arguments to start the CLI headless. <paramref name="conversation"/>
    /// resumes one; <paramref name="message"/> is the prompt for per-turn CLIs.
    /// </summary>
    public static List<string> Arguments(this AgentKind kind, string? conversation, AgentPermission permission, string? message)
    {
        var args = new List<string>();
        switch (kind)
        {
            case AgentKind.Agy:
                args.AddRange(new[] { "--input-format=stream-json", "--output-format=stream-json", "--print=" });
                if (conversation is not null) args.AddRange(new[] { "--conversation", conversation });
                if (permission == AgentPermission.Edits) args.AddRange(new[] { "--mode", "accept-edits" });
                if (permission == AgentPermission.All) args.AddRange(new[] { "--mode", "auto" });
                break;
            case AgentKind.Claude:
                args.AddRange(new[] { "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages" });
                if (conversation is not null) args.AddRange(new[] { "--resume", conversation });
                if (permission == AgentPermission.Edits) args.AddRange(new[] { "--permission-mode", "acceptEdits" });
                if (permission == AgentPermission.All) args.AddRange(new[] { "--permission-mode", "bypassPermissions" });
                break;
            case AgentKind.Qwen:
                args.AddRange(new[] { "-p", message ?? "", "-o", "stream-json" });
                if (conversation is not null) args.AddRange(new[] { "--resume", conversation });
                break;
            case AgentKind.Codex:
                args.Add("exec");
                if (conversation is not null) args.AddRange(new[] { "resume", conversation });
                args.AddRange(new[] { "--json", "--skip-git-repo-check" });
                if (permission == AgentPermission.Edits) args.AddRange(new[] { "-s", "workspace-write" });
                if (permission == AgentPermission.All) args.Add("--dangerously-bypass-approvals-and-sandbox");
                args.Add(message ?? "");
                break;
        }
        return args;
    }

    /// <summary>One user message for persistent CLIs, as the line they read.</summary>
    public static string InputLine(this AgentKind kind, string message)
    {
        object payload = kind == AgentKind.Agy
            ? new { @event = "user", message = new { content = message } }
            : new { type = "user", message = new { role = "user", content = message } };
        return JsonSerializer.Serialize(payload) + "\n";
    }

    public static IAgentOutputParser CreateParser(this AgentKind kind) => kind switch
    {
        AgentKind.Agy => new AgyParser(),
        AgentKind.Codex => new CodexParser(),
        _ => new ClaudeStreamParser(),
    };

    /// <summary>The command that opens the CLI's own screen, on the same conversation.</summary>
    public static string TerminalCommand(this AgentKind kind, string? conversation)
    {
        var name = kind.CommandName();
        if (conversation is null) return name;
        var id = "'" + conversation.Replace("'", "''") + "'";
        return kind switch
        {
            AgentKind.Agy => $"agy --conversation {id}",
            AgentKind.Codex => $"codex resume {id}",
            _ => $"{name} --resume {id}",
        };
    }
}
