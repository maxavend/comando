namespace Comando.Core.Assistant;

/// <summary>A command the assistant proposes. Nothing runs until the person clicks.</summary>
public sealed class AssistantProposal
{
    public string Command { get; set; } = "";

    /// <summary>What the command does, in plain words.</summary>
    public string Explanation { get; set; } = "";

    /// <summary>Written by the model rather than taken from a recipe; it asks before running if it changes things.</summary>
    public bool IsGenerated { get; set; }
}

/// <summary>One point of a guide answer: an icon, a short title and a line about it.</summary>
public sealed class AssistantPoint
{
    public string Glyph { get; set; } = "";
    public string Title { get; set; } = "";
    public string Detail { get; set; } = "";
}

/// <summary>The assistant's answer to a request, stored with its entry.</summary>
public sealed class AssistantReply
{
    public string? Explanation { get; set; }
    public List<AssistantProposal> Proposals { get; set; } = [];
    public List<AssistantPoint> Points { get; set; } = [];

    /// <summary>Tools that would do it, not installed yet, with the command that installs each.</summary>
    public List<AssistantProposal> ToolsToInstall { get; set; } = [];

    public string? Error { get; set; }

    /// <summary>The model is still writing.</summary>
    public bool IsWriting { get; set; }

    public AssistantReply Copy() => new()
    {
        Explanation = Explanation,
        Proposals = [.. Proposals],
        Points = [.. Points],
        ToolsToInstall = [.. ToolsToInstall],
        Error = Error,
        IsWriting = IsWriting,
    };
}
