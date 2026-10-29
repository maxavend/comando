using System.Collections.ObjectModel;
using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;
using Comando.Core.Language;

namespace Comando.Core.Models;

public enum EntryKind
{
    Command,
    Interactive,
    /// <summary>A request in plain words answered by the assistant.</summary>
    Assistant,
    /// <summary>The start of a conversation with an AI agent CLI (<c>agy</c>, <c>claude</c>…).</summary>
    AgentStart,
    /// <summary>A message to that agent and its reply.</summary>
    Agent,
}

/// <summary>One message pair in the chat: the command the user sent and what the shell answered.</summary>
public sealed partial class CommandEntry : ObservableObject
{
    public const int PlainOutputLimit = 64 * 1024;

    public CommandEntry()
    {
        Command = "";
        Output = [];
        PlainOutput = "";
    }

    public Guid Id { get; set; } = Guid.NewGuid();

    [ObservableProperty]
    public partial string Command { get; set; }

    /// <summary>Raw output bytes, including ANSI styling, so colors survive relaunch.</summary>
    [ObservableProperty]
    public partial byte[] Output { get; set; }

    /// <summary>Output without escape sequences, for search. Capped in size.</summary>
    [ObservableProperty]
    public partial string PlainOutput { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Succeeded), nameof(WasInterrupted))]
    public partial int? ExitCode { get; set; }

    public DateTimeOffset StartedAt { get; set; } = DateTimeOffset.Now;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsFinished), nameof(WasInterrupted), nameof(Duration))]
    public partial DateTimeOffset? FinishedAt { get; set; }

    public string Directory { get; set; } = "";

    public EntryKind Kind { get; set; } = EntryKind.Command;

    [ObservableProperty]
    public partial bool Truncated { get; set; }

    /// <summary>Folder the shell was in after the command, when the command changed it.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(MovedTo))]
    public partial string? EndDirectory { get; set; }

    [JsonIgnore]
    public bool IsFinished => FinishedAt is not null;

    /// <summary>Finished without an exit code: the app quit or the shell restarted mid-command.</summary>
    [JsonIgnore]
    public bool WasInterrupted => FinishedAt is not null && ExitCode is null;

    [JsonIgnore]
    public bool Succeeded => ExitCode == 0;

    /// <summary>The folder change this command caused, if any.</summary>
    [JsonIgnore]
    public string? MovedTo => EndDirectory is { } end && end != Directory ? end : null;

    [JsonIgnore]
    public TimeSpan? Duration => FinishedAt - StartedAt;
}

/// <summary>A conversation in the sidebar: one shell with its own folder and history.</summary>
public sealed partial class TerminalSession : ObservableObject
{
    public TerminalSession()
    {
        Directory = "";
        LastActivity = DateTimeOffset.Now;
    }

    public Guid Id { get; set; } = Guid.NewGuid();

    /// <summary>Set when the user renames the session.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DisplayName))]
    public partial string? CustomName { get; set; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(DisplayName))]
    public partial string Directory { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;

    [ObservableProperty]
    public partial DateTimeOffset LastActivity { get; set; }

    [ObservableProperty]
    public partial string? LastCommand { get; set; }

    [ObservableProperty]
    public partial int UnreadCount { get; set; }

    /// <summary>Folders visited in this session, most recent first.</summary>
    public List<string> RecentDirectories { get; set; } = [];

    /// <summary>Pinned sessions stay at the top of the sidebar.</summary>
    [ObservableProperty]
    public partial bool IsPinned { get; set; }

    /// <summary>Optional emoji shown in the avatar instead of the folder icon.</summary>
    [ObservableProperty]
    public partial string? Emoji { get; set; }

    /// <summary>Index into the app's session colors for the avatar background.</summary>
    [ObservableProperty]
    public partial int ColorIndex { get; set; }

    public ObservableCollection<CommandEntry> Entries { get; set; } = [];

    [JsonIgnore]
    public string DisplayName => string.IsNullOrWhiteSpace(CustomName) ? FolderName.Display(Directory) : CustomName;

    public void Remember(string folder)
    {
        RecentDirectories.Remove(folder);
        RecentDirectories.Insert(0, folder);
        if (RecentDirectories.Count > 8) RecentDirectories.RemoveRange(8, RecentDirectories.Count - 8);
    }
}
