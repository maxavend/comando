using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using Comando.Core.Pty;
using Comando.Core.Terminal;

namespace Comando.Core.Shell;

public enum ShellPhase
{
    NotStarted,
    Starting,
    Idle,
    Running,
    Interactive,
    Exited,
}

/// <summary>
/// One PowerShell process running in a pseudoconsole, with the app's shell
/// integration loaded. Converts the byte stream into command lifecycle
/// events and live output.
/// </summary>
public sealed partial class ShellSession : ObservableObject, IDisposable
{
    private readonly Func<IPseudoTerminal> _terminalFactory;
    private readonly IDispatcher _dispatcher;
    private readonly string _appVersion;
    private IPseudoTerminal? _terminal;
    private StreamParser _parser = new();
    private (Guid EntryId, string Command)? _queued;
    private bool _outputStarted;
    private (int Columns, int Rows) _chatSize = (100, 40);

    // Embedded terminal plumbing.
    private readonly List<byte> _interactiveBacklog = [];
    private Action<byte[]>? _interactiveSink;

    /// <summary>The embedded terminal's visible text, kept when an interactive program ends.</summary>
    public Func<string?>? TranscriptProvider { get; set; }

    public ShellSession(Guid id, string directory, Func<IPseudoTerminal> terminalFactory, IDispatcher dispatcher, string appVersion = "0")
    {
        Id = id;
        Directory = directory;
        _terminalFactory = terminalFactory;
        _dispatcher = dispatcher;
        _appVersion = appVersion;
    }

    public Guid Id { get; }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsBusy))]
    public partial ShellPhase Phase { get; private set; }

    [ObservableProperty]
    public partial string Directory { get; private set; }

    [ObservableProperty]
    public partial LiveOutput? Live { get; private set; }

    public IReadOnlyList<string> PathEntries { get; private set; } = [];

    /// <summary>First words that should open the embedded terminal right away.</summary>
    public IReadOnlySet<string> InteractiveCommands { get; set; } = new HashSet<string>();

    public bool IsBusy => Phase is ShellPhase.Running or ShellPhase.Interactive;

    public event Action<ShellSession, string>? DirectoryChanged;
    public event Action<ShellSession, CommandResult>? Finished;
    public event Action<ShellSession>? Exited;

    // Lifecycle

    public void Start()
    {
        if (Phase is not (ShellPhase.NotStarted or ShellPhase.Exited)) return;
        _parser = new StreamParser();
        Phase = ShellPhase.Starting;
        if (!System.IO.Directory.Exists(Directory))
        {
            Directory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        var terminal = _terminalFactory();
        _terminal = terminal;
        terminal.DataReceived += bytes => _dispatcher.Post(() =>
        {
            if (ReferenceEquals(_terminal, terminal)) Receive(bytes);
        });
        terminal.Exited += _ => _dispatcher.Post(() =>
        {
            if (ReferenceEquals(_terminal, terminal)) ProcessTerminated();
        });

        var shell = ShellIntegration.FindShell();
        try
        {
            terminal.Start(new PtyStartInfo(
                shell,
                ShellIntegration.Arguments(ShellIntegration.ScriptPath),
                ShellIntegration.BuildEnvironment(_appVersion),
                Directory,
                _chatSize.Columns,
                _chatSize.Rows));
        }
        catch (InvalidOperationException)
        {
            _terminal = null;
            terminal.Dispose();
            Phase = ShellPhase.Exited;
            Exited?.Invoke(this);
        }
    }

    public void Terminate() => _terminal?.Dispose();

    public void Restart()
    {
        var terminal = _terminal;
        _terminal = null;
        terminal?.Dispose();
        if (Live is not null) FinishCurrent(exitCode: null);
        Phase = ShellPhase.NotStarted;
        Start();
    }

    public void Dispose() => Terminate();

    // Input

    /// <summary>Runs <paramref name="command"/> as a new command line.</summary>
    public void Run(string command, Guid entryId)
    {
        switch (Phase)
        {
            case ShellPhase.NotStarted or ShellPhase.Exited:
                _queued = (entryId, command);
                Start();
                return;
            case ShellPhase.Starting:
                _queued = (entryId, command);
                return;
            case ShellPhase.Running or ShellPhase.Interactive:
                return;
        }
        Live = new LiveOutput(entryId, command, _chatSize.Rows, _dispatcher);
        _outputStarted = false;
        Phase = ShellPhase.Running;
        // PSReadLine has no bracketed paste: the encoded line keeps multi-line
        // commands and special characters intact. The CR accepts the line.
        Send(Encoding.UTF8.GetBytes(ShellIntegration.Encode(command) + "\r"));
    }

    /// <summary>Sends a line of input to the running program (stdin).</summary>
    public void SendLine(string text) => Send(Encoding.UTF8.GetBytes(text + "\r"));

    public void SendRaw(ReadOnlySpan<byte> bytes) => Send(bytes);

    public void Interrupt() => Send([0x03]);

    /// <summary>
    /// Quits the running program, gently first: Ctrl+C twice, which is what
    /// agents and most programs expect. The shell itself stays.
    /// </summary>
    public async Task QuitForegroundAsync()
    {
        if (!IsBusy) return;
        Interrupt();
        await Task.Delay(300);
        if (IsBusy) Interrupt();
    }

    private void Send(ReadOnlySpan<byte> bytes)
    {
        if (_terminal is { IsRunning: true } terminal) terminal.Write(bytes);
    }

    // Window size

    /// <summary>Size used while output is shown as chat bubbles.</summary>
    public void SetChatSize(int columns, int rows)
    {
        columns = Math.Max(20, columns);
        if (_chatSize == (columns, rows)) return;
        _chatSize = (columns, rows);
        if (Phase != ShellPhase.Interactive) ApplyWindowSize(columns, rows);
    }

    public void ApplyWindowSize(int columns, int rows) => _terminal?.Resize(columns, rows);

    // Embedded terminal

    /// <summary>
    /// Connects the embedded terminal view. Bytes received before it attached
    /// are replayed so the program's first screen isn't lost.
    /// </summary>
    public void AttachInteractiveSink(Action<byte[]> sink)
    {
        _interactiveSink = sink;
        if (_interactiveBacklog.Count > 0)
        {
            sink([.. _interactiveBacklog]);
            _interactiveBacklog.Clear();
        }
    }

    public void DetachInteractiveSink() => _interactiveSink = null;

    /// <summary>Switches the running command to the embedded terminal.</summary>
    public void OpenInTerminal()
    {
        if (Phase == ShellPhase.Running && Live is { } live) EnterInteractive([.. live.Raw]);
    }

    private void EnterInteractive(IEnumerable<byte> replay)
    {
        if (Live is not { } live) return;
        Phase = ShellPhase.Interactive;
        live.IsInteractive = true;
        _interactiveBacklog.Clear();
        _interactiveBacklog.AddRange(replay);
    }

    // Output handling

    internal void Receive(byte[] bytes)
    {
        foreach (var parsed in _parser.Feed(bytes))
        {
            if (parsed.Token is TerminalToken.Osc osc && HandleIntegration(osc.Payload)) continue;
            switch (Phase)
            {
                case ShellPhase.Running:
                    if (Live is not { } live || !_outputStarted) continue;
                    if (parsed.Token is TerminalToken.Csi csi && EntersAlternateScreen(csi.Sequence))
                    {
                        EnterInteractive(parsed.Raw);
                        continue;
                    }
                    live.Append(parsed);
                    break;
                case ShellPhase.Interactive:
                    if (_interactiveSink is { } sink) sink(parsed.Raw);
                    else _interactiveBacklog.AddRange(parsed.Raw);
                    break;
            }
        }
    }

    /// <summary>Handles the shell integration OSCs. Returns false for any other OSC.</summary>
    private bool HandleIntegration(string payload)
    {
        if (payload.StartsWith("133;", StringComparison.Ordinal))
        {
            var parts = payload.Split(';');
            switch (parts.Length > 1 ? parts[1] : "")
            {
                case "A":
                    PromptReady();
                    break;
                case "C":
                    _outputStarted = true;
                    // AI agents ask questions with arrow-key menus even before
                    // they take the full screen, so they always get the terminal.
                    if (Live is { } live && (InteractiveCommands.Contains(FirstWord(live.Command)) || AICommandLine.IsAgent(live.Command)))
                    {
                        EnterInteractive([]);
                    }
                    break;
                case "D":
                    int? code = parts.Length > 2 && int.TryParse(parts[2], out var value) ? value : null;
                    if (IsBusy) FinishCurrent(code);
                    break;
            }
            return true;
        }
        if (payload.StartsWith(ShellIntegration.DirectoryOsc, StringComparison.Ordinal))
        {
            UpdateDirectory(payload[ShellIntegration.DirectoryOsc.Length..]);
            return true;
        }
        if (payload.StartsWith(ShellIntegration.PathOsc, StringComparison.Ordinal))
        {
            PathEntries = payload[ShellIntegration.PathOsc.Length..]
                .Split(';', StringSplitOptions.RemoveEmptyEntries);
            return true;
        }
        return false;
    }

    private void PromptReady()
    {
        if (Phase == ShellPhase.Starting) Phase = ShellPhase.Idle;
        if (Phase == ShellPhase.Idle && _queued is { } queued)
        {
            _queued = null;
            Run(queued.Command, queued.EntryId);
        }
    }

    private void UpdateDirectory(string path)
    {
        if (path.Length == 0 || path == Directory) return;
        Directory = path;
        DirectoryChanged?.Invoke(this, path);
    }

    private void FinishCurrent(int? exitCode)
    {
        if (Live is not { } live) return;
        string? transcript = null;
        if (live.IsInteractive && TranscriptProvider?.Invoke()?.Trim() is { Length: > 0 } text)
        {
            transcript = text;
        }
        var result = new CommandResult(
            live.EntryId,
            exitCode,
            [.. live.Raw],
            live.Truncated,
            live.IsInteractive,
            DateTimeOffset.Now,
            transcript);
        Live = null;
        _interactiveSink = null;
        _interactiveBacklog.Clear();
        if (Phase != ShellPhase.Exited) Phase = ShellPhase.Idle;
        ApplyWindowSize(_chatSize.Columns, _chatSize.Rows);
        Finished?.Invoke(this, result);
    }

    private void ProcessTerminated()
    {
        if (Live is not null) FinishCurrent(exitCode: 0);
        Phase = ShellPhase.Exited;
        Exited?.Invoke(this);
    }

    // Helpers

    public static bool EntersAlternateScreen(CsiSequence csi) =>
        csi.Marker == (byte)'?' && csi.Final == (byte)'h' && csi.Params.Any(p => p is 47 or 1047 or 1049);

    /// <summary>The program a command line starts: <c>C:\tools\git.exe status</c> → <c>git</c>.</summary>
    public static string FirstWord(string command)
    {
        var trimmed = command.TrimStart(' ');
        var end = trimmed.IndexOfAny([' ', '\n']);
        var word = end < 0 ? trimmed : trimmed[..end];
        var name = word.Split('/', '\\')[^1];
        return name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name;
    }
}
