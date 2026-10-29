using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Pty;
using Comando.Core.Shell;
using Comando.Core.Terminal;

namespace Comando.Core.Services;

/// <summary>A risky command waiting for the person to confirm it.</summary>
public sealed record PendingCommand(string Command, Guid SessionId, CommandRisk Risk, string? RecycleBinAlternative = null);

/// <summary>
/// App-wide owner of the running shells. Bridges shell events into the
/// models that the views display.
/// </summary>
public sealed partial class TerminalController : ObservableObject
{
    private readonly Func<IPseudoTerminal> _terminalFactory;
    private readonly IDispatcher _dispatcher;
    private readonly SessionStore _store;
    private readonly string _appVersion;
    private readonly Dictionary<Guid, ShellSession> _shells = [];

    public TerminalController(Func<IPseudoTerminal> terminalFactory, IDispatcher dispatcher, SessionStore store, string appVersion = "0")
    {
        _terminalFactory = terminalFactory;
        _dispatcher = dispatcher;
        _store = store;
        _appVersion = appVersion;

        var saved = store.Load();
        RepairInterruptedEntries(saved);
        Sessions = new ObservableCollection<TerminalSession>(saved.OrderByDescending(s => s.IsPinned).ThenByDescending(s => s.LastActivity));
        SelectedSession = Sessions.FirstOrDefault() ?? CreateSession();
    }

    /// <summary>Sessions in the sidebar: pinned first, then by activity.</summary>
    public ObservableCollection<TerminalSession> Sessions { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(SelectedShell))]
    public partial TerminalSession? SelectedSession { get; set; }

    /// <summary>A risky command shown in a confirmation dialog before it runs.</summary>
    [ObservableProperty]
    public partial PendingCommand? PendingCommand { get; set; }

    /// <summary>Confirm before commands that are hard to undo.</summary>
    public bool ConfirmRiskyCommands { get; set; } = true;

    /// <summary>First words that open the embedded terminal right away.</summary>
    public IReadOnlySet<string> InteractiveCommands { get; set; } =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "vim", "nvim", "nano", "ssh", "python", "node", "htop", "less", "edit" };

    public ShellSession? SelectedShell => SelectedSession is { } session ? Shell(session) : null;

    public bool HasRunningCommands => _shells.Values.Any(shell => shell.IsBusy);

    /// <summary>Where the selected session is, without starting its shell.</summary>
    private string? CurrentDirectory => SelectedSession is not { } session ? null
        : _shells.TryGetValue(session.Id, out var shell) ? shell.Directory : session.Directory;

    partial void OnSelectedSessionChanged(TerminalSession? value)
    {
        if (value is null) return;
        value.UnreadCount = 0;
    }

    // Sessions

    public TerminalSession CreateSession(string? directory = null)
    {
        var session = new TerminalSession
        {
            Directory = directory ?? CurrentDirectory ?? FolderName.Home,
            ColorIndex = Sessions?.Count ?? 0,
        };
        session.Remember(session.Directory);
        Sessions!.Insert(Sessions.Count(s => s.IsPinned), session);
        SelectedSession = session;
        Save();
        return session;
    }

    public void Delete(TerminalSession session)
    {
        if (_shells.Remove(session.Id, out var shell)) shell.Dispose();
        var index = Sessions.IndexOf(session);
        Sessions.Remove(session);
        if (SelectedSession == session)
        {
            SelectedSession = Sessions.Count > 0 ? Sessions[Math.Min(index, Sessions.Count - 1)] : CreateSession();
        }
        Save();
    }

    public void Rename(TerminalSession session, string name)
    {
        var trimmed = name.Trim();
        session.CustomName = trimmed.Length == 0 ? null : trimmed;
        Save();
    }

    public void TogglePin(TerminalSession session)
    {
        session.IsPinned = !session.IsPinned;
        Reorder(session);
        Save();
    }

    public void ClearHistory(TerminalSession session)
    {
        var running = _shells.GetValueOrDefault(session.Id)?.Live?.EntryId;
        foreach (var entry in session.Entries.Where(e => e.Id != running).ToList())
        {
            session.Entries.Remove(entry);
        }
        session.LastCommand = null;
        Save();
    }

    /// <summary>Moves the selection up or down the sidebar.</summary>
    public void SelectAdjacentSession(int offset)
    {
        if (Sessions.Count == 0 || SelectedSession is null) return;
        var index = Sessions.IndexOf(SelectedSession);
        SelectedSession = Sessions[(index + offset + Sessions.Count) % Sessions.Count];
    }

    // Shells

    /// <summary>The shell for a session, started on first use.</summary>
    public ShellSession Shell(TerminalSession session)
    {
        if (_shells.TryGetValue(session.Id, out var existing)) return existing;
        var shell = new ShellSession(session.Id, session.Directory, _terminalFactory, _dispatcher, _appVersion)
        {
            InteractiveCommands = InteractiveCommands,
        };
        shell.DirectoryChanged += OnDirectoryChanged;
        shell.Finished += OnFinished;
        _shells[session.Id] = shell;
        shell.Start();
        return shell;
    }

    public void RestartShell(TerminalSession session) => Shell(session).Restart();

    public void TerminateAll()
    {
        foreach (var shell in _shells.Values) shell.Dispose();
        _store.Save(Sessions);
    }

    // Commands

    /// <summary>Handles text from the composer: a new command, or input for the running one.</summary>
    public void Submit(string text, TerminalSession session, bool confirmed = false)
    {
        var shell = Shell(session);
        if (shell.IsBusy)
        {
            shell.SendLine(text);
            return;
        }
        var command = text.Trim();
        if (command.Length == 0) return;

        if (!confirmed && ConfirmRiskyCommands)
        {
            // Deleting files always offers the recoverable option: the Recycle Bin.
            var recycle = RecycleBinConverter.Command(command);
            var risk = DangerDetector.Risk(command) ?? (recycle is null ? null : new CommandRisk(
                "Este comando borra archivos para siempre",
                "No pasan por la Papelera de reciclaje. Si los envías a la Papelera, podrás recuperarlos."));
            if (risk is not null)
            {
                PendingCommand = new PendingCommand(command, session.Id, risk, recycle);
                return;
            }
        }

        if (command.ToLowerInvariant() is "clear" or "cls" or "clear-host" or "reset")
        {
            ClearHistory(session);
            return;
        }

        var entry = new CommandEntry { Command = command, Directory = shell.Directory };
        session.Entries.Add(entry);
        session.LastActivity = entry.StartedAt;
        session.LastCommand = command;
        Reorder(session);
        Save();
        shell.InteractiveCommands = InteractiveCommands;
        shell.Run(command, entry.Id);
    }

    /// <summary>Runs the command the person confirmed in the risk dialog.</summary>
    public void ConfirmPendingCommand()
    {
        if (PendingCommand is not { } pending || Find(pending.SessionId) is not { } session) return;
        PendingCommand = null;
        Submit(pending.Command, session, confirmed: true);
    }

    /// <summary>Runs the recoverable version of a pending delete: send to the Recycle Bin.</summary>
    public void SendToRecycleBinInstead()
    {
        if (PendingCommand is not { RecycleBinAlternative: { } recycle } pending || Find(pending.SessionId) is not { } session) return;
        PendingCommand = null;
        Submit(recycle, session, confirmed: true);
    }

    public void CancelPendingCommand() => PendingCommand = null;

    public void Stop(TerminalSession session) => _ = Shell(session).QuitForegroundAsync();

    // Shell events

    private void OnDirectoryChanged(ShellSession shell, string directory)
    {
        if (Find(shell.Id) is not { } session) return;
        session.Directory = directory;
        session.Remember(directory);
        Save();
    }

    private void OnFinished(ShellSession shell, CommandResult result)
    {
        if (Find(shell.Id) is not { } session) return;
        var entry = session.Entries.FirstOrDefault(e => e.Id == result.EntryId);
        if (entry is null) return;
        var plain = OutputRenderer.PlainText(result.Output);
        entry.Output = result.Output;
        entry.PlainOutput = plain.Length > CommandEntry.PlainOutputLimit ? plain[..CommandEntry.PlainOutputLimit] : plain;
        entry.Truncated = result.Truncated;
        entry.Transcript = result.Transcript;
        entry.ExitCode = result.ExitCode;
        entry.EndDirectory = shell.Directory;
        entry.Kind = result.WasInteractive ? EntryKind.Interactive : EntryKind.Command;
        entry.FinishedAt = result.FinishedAt;
        session.LastActivity = result.FinishedAt;
        if (SelectedSession != session) session.UnreadCount++;
        Save();
    }

    // Helpers

    private TerminalSession? Find(Guid id) => Sessions.FirstOrDefault(s => s.Id == id);

    /// <summary>Keeps the sidebar order: pinned first, then most recent activity.</summary>
    private void Reorder(TerminalSession session)
    {
        var from = Sessions.IndexOf(session);
        if (from < 0) return;
        var to = session.IsPinned ? 0 : Sessions.Count(s => s.IsPinned && s != session);
        if (from != to) Sessions.Move(from, to);
    }

    /// <summary>Commands left running when the app quit can't finish anymore.</summary>
    private static void RepairInterruptedEntries(IEnumerable<TerminalSession> sessions)
    {
        foreach (var entry in sessions.SelectMany(s => s.Entries).Where(e => e.FinishedAt is null))
        {
            entry.FinishedAt = entry.StartedAt;
        }
    }

    private void Save() => _store.ScheduleSave(Sessions, _dispatcher);
}
