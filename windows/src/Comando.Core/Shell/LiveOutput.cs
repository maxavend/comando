using System.Text.RegularExpressions;
using CommunityToolkit.Mvvm.ComponentModel;
using Comando.Core.Terminal;

namespace Comando.Core.Shell;

/// <summary>Runs work on the UI thread. The app wraps its DispatcherQueue; tests run it inline.</summary>
public interface IDispatcher
{
    void Post(Action action);
}

public sealed class InlineDispatcher : IDispatcher
{
    public static readonly InlineDispatcher Instance = new();
    public void Post(Action action) => action();
}

/// <summary>Output of the command that is currently running, observed by its bubble.</summary>
public sealed partial class LiveOutput : ObservableObject
{
    public const int RawLimit = 1 << 20;

    private readonly IDispatcher _dispatcher;
    private bool _updateScheduled;

    public LiveOutput(Guid entryId, string command, int screenRows, IDispatcher dispatcher)
    {
        EntryId = entryId;
        Command = command;
        StartedAt = DateTimeOffset.Now;
        LastOutputAt = StartedAt;
        Buffer = new LineBuffer { ScreenRows = screenRows };
        _dispatcher = dispatcher;
    }

    public Guid EntryId { get; }
    public string Command { get; }
    public DateTimeOffset StartedAt { get; }

    /// <summary>Bumped (at most ~10 times per second) when <see cref="Buffer"/> changes.</summary>
    [ObservableProperty]
    public partial int Version { get; private set; }

    [ObservableProperty]
    public partial bool HasOutput { get; private set; }

    [ObservableProperty]
    public partial bool IsInteractive { get; set; }

    /// <summary>A local server address the command printed (e.g. a dev server).</summary>
    [ObservableProperty]
    public partial Uri? LocalUrl { get; private set; }

    /// <summary>When output last arrived; quiet commands are shown as “still active”.</summary>
    public DateTimeOffset LastOutputAt { get; private set; }

    public LineBuffer Buffer { get; }
    public List<byte> Raw { get; } = [];
    public bool Truncated { get; private set; }

    public void Append(ParsedToken token)
    {
        Buffer.Apply(token.Token);
        Raw.AddRange(token.Raw);
        LastOutputAt = DateTimeOffset.Now;
        if (Raw.Count > RawLimit * 2)
        {
            // Keep the most recent output, like a terminal's scrollback.
            Raw.RemoveRange(0, Raw.Count - RawLimit);
            Truncated = true;
        }
        ScheduleUpdate();
    }

    private void ScheduleUpdate()
    {
        if (_updateScheduled) return;
        _updateScheduled = true;
        _ = Task.Delay(100).ContinueWith(_ => _dispatcher.Post(PublishUpdate), TaskScheduler.Default);
    }

    private void PublishUpdate()
    {
        _updateScheduled = false;
        Version = unchecked(Version + 1);
        if (!HasOutput && !Buffer.IsEmpty) HasOutput = true;
        if (LocalUrl is null)
        {
            var recent = string.Join('\n', Buffer.Lines.TakeLast(40).Select(line => string.Concat(line.Select(cell => cell.Character))));
            LocalUrl = FirstLocalUrl(recent);
        }
    }

    internal static Uri? FirstLocalUrl(string text)
    {
        var match = LocalUrlPattern().Match(text);
        if (!match.Success) return null;
        var value = match.Value.TrimEnd('.', ',', ')', ']');
        // 0.0.0.0 means “every address”; the browser needs a real one.
        value = value.Replace("://0.0.0.0", "://localhost");
        return Uri.TryCreate(value, UriKind.Absolute, out var url) ? url : null;
    }

    [GeneratedRegex(@"https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])(:\d+)?(/[^\s]*)?")]
    private static partial Regex LocalUrlPattern();
}

/// <summary>What a finished command produced.</summary>
public sealed record CommandResult(
    Guid EntryId,
    int? ExitCode,
    byte[] Output,
    bool Truncated,
    bool WasInteractive,
    DateTimeOffset FinishedAt);
