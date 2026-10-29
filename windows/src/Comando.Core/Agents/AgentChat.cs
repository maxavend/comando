using CommunityToolkit.Mvvm.ComponentModel;
using Comando.Core.Shell;

namespace Comando.Core.Agents;

/// <summary>
/// An open conversation with an agent CLI in one session. Each message gets
/// its own <see cref="AgentReply"/>, filled as the answer streams in.
/// </summary>
/// <remarks>
/// Process output arrives on background threads and is moved to the UI
/// thread with the <see cref="IDispatcher"/>, in the order it was printed.
/// </remarks>
public sealed partial class AgentChat : ObservableObject
{
    private static readonly TimeSpan SilenceLimit = TimeSpan.FromSeconds(45);

    private readonly IDispatcher _dispatcher;
    private readonly Func<string, IReadOnlyList<string>, string?> _findExecutable;
    private AgentProcess? _process;
    private IAgentOutputParser _parser;
    private Turn? _current;
    private string _directory;
    private IReadOnlyList<string> _path;
    private DateTimeOffset _lastOutput = DateTimeOffset.Now;
    private bool _askedForTerminal;

    /// <summary>The reply being written and where it goes.</summary>
    private sealed class Turn(Guid id, AgentReply reply, Action<AgentReply> onUpdate, Action<AgentReply> onFinished)
    {
        public Guid Id { get; } = id;
        public AgentReply Reply { get; set; } = reply;
        public Action<AgentReply> OnUpdate { get; } = onUpdate;
        public Action<AgentReply> OnFinished { get; } = onFinished;
    }

    public AgentChat(AgentKind kind, Guid sessionId, string directory, IReadOnlyList<string> path, IDispatcher dispatcher,
        string? conversationId = null, AgentPermission permission = AgentPermission.Ask,
        Func<string, IReadOnlyList<string>, string?>? findExecutable = null)
    {
        Kind = kind;
        SessionId = sessionId;
        _directory = directory;
        _path = path;
        _dispatcher = dispatcher;
        _findExecutable = findExecutable ?? ((name, entries) => AgentProcess.Executable(name, entries));
        _parser = kind.CreateParser();
        ConversationId = conversationId;
        Permission = permission;
        IsResponding = false;
        IsReady = false;
        StartupError = null;
    }

    public AgentKind Kind { get; }
    public Guid SessionId { get; }

    [ObservableProperty]
    public partial string? ConversationId { get; private set; }

    [ObservableProperty]
    public partial AgentPermission Permission { get; private set; }

    [ObservableProperty]
    public partial bool IsResponding { get; private set; }

    /// <summary>The CLI is up and waiting for a message.</summary>
    [ObservableProperty]
    public partial bool IsReady { get; private set; }

    /// <summary>Why the CLI couldn't start, when it quit before being ready.</summary>
    [ObservableProperty]
    public partial string? StartupError { get; private set; }

    /// <summary>A new conversation id, to save it with the session and resume it later.</summary>
    public event Action<string>? ConversationStarted;

    /// <summary>
    /// The CLI is asking for something only its own screen can do (sign in,
    /// update, a yes/no question), or went silent: open the terminal.
    /// </summary>
    public event Action<string>? NeedsTerminal;

    public bool IsInstalled => _findExecutable(Kind.CommandName(), _path) is not null;

    /// <summary>
    /// Starts the CLI ahead of the first message, so it's ready when the
    /// person writes. Per-message CLIs are ready right away.
    /// </summary>
    public void WarmUp()
    {
        StartupError = null;
        if (Kind.Transport() != AgentTransport.Persistent)
        {
            IsReady = IsInstalled;
            return;
        }
        if (_process?.IsRunning == true) return;
        IsReady = false;
        Start(message: null);
        // Some CLIs only introduce themselves after the first message.
        var started = _process;
        _ = Task.Delay(TimeSpan.FromSeconds(5)).ContinueWith(_ => _dispatcher.Post(() =>
        {
            if (_process is not null && ReferenceEquals(_process, started) && _process.IsRunning) IsReady = true;
        }), TaskScheduler.Default);
    }

    /// <summary>
    /// Sends a message. The answer arrives through <paramref name="onUpdate"/>
    /// as it streams, and once more through <paramref name="onFinished"/>.
    /// Each call gets a fresh copy of the reply.
    /// </summary>
    public void Send(string message, Action<AgentReply> onUpdate, Action<AgentReply> onFinished, string directory, IReadOnlyList<string> path)
    {
        if (IsResponding) return;
        _directory = directory;
        _path = path;
        var turn = new Turn(Guid.NewGuid(), new AgentReply(), onUpdate, onFinished);
        _current = turn;
        IsResponding = true;
        StartupError = null;
        onUpdate(turn.Reply.Copy());
        if (Kind.Transport() == AgentTransport.Persistent)
        {
            if (_process?.IsRunning != true) Start(message: null);
            _process?.Write(Kind.InputLine(message));
        }
        else
        {
            Start(message);
        }
        if (_process is null)
        {
            FinishTurn(new AgentEvent.Failed($"No se pudo abrir {Kind.CommandName()}."));
            return;
        }
        WatchForSilence(turn.Id);
    }

    /// <summary>
    /// Nothing at all for a long while: it's probably waiting on something
    /// only its own screen shows.
    /// </summary>
    private async void WatchForSilence(Guid id)
    {
        while (true)
        {
            await Task.Delay(TimeSpan.FromSeconds(5)).ConfigureAwait(false);
            var stop = false;
            var tcs = new TaskCompletionSource();
            _dispatcher.Post(() =>
            {
                if (!IsResponding || _current?.Id != id || _askedForTerminal)
                {
                    stop = true;
                }
                else if (_current.Reply.Steps.Count == 0 && DateTimeOffset.Now - _lastOutput > SilenceLimit)
                {
                    _askedForTerminal = true;
                    stop = true;
                    NeedsTerminal?.Invoke($"{Kind.CommandName()} no respondió");
                }
                tcs.TrySetResult();
            });
            await tcs.Task.ConfigureAwait(false);
            if (stop) return;
        }
    }

    /// <summary>
    /// What the agent may do from now on. A persistent CLI restarts so the
    /// new mode applies; the conversation goes on.
    /// </summary>
    public void Allow(AgentPermission permission)
    {
        Permission = permission;
        if (Kind.Transport() == AgentTransport.Persistent)
        {
            _process?.CloseInput();
            _process = null;
        }
    }

    /// <summary>Stops the answer in progress.</summary>
    public void Stop()
    {
        _process?.Stop();
        if (Kind.Transport() == AgentTransport.Persistent) _process = null;
        FinishTurn(new AgentEvent.TurnFinished(Array.Empty<string>(), null), stopped: true);
    }

    /// <summary>
    /// Lets the CLI's own screen take the conversation for a while: the
    /// headless process closes, and the next message resumes it.
    /// </summary>
    public void Pause()
    {
        if (IsResponding) Stop();
        _process?.Stop();
        _process = null;
        IsReady = false;
    }

    /// <summary>Ends the conversation and the CLI with it.</summary>
    public void End()
    {
        _process?.Stop();
        _process = null;
        if (IsResponding) FinishTurn(new AgentEvent.TurnFinished(Array.Empty<string>(), null), stopped: true);
    }

    // Process

    private void Start(string? message)
    {
        if (_findExecutable(Kind.CommandName(), _path) is not { } executable) return;
        _parser = Kind.CreateParser();
        var arguments = Kind.Arguments(ConversationId, Permission, message);
        AgentProcess? started = null;
        try
        {
            started = new AgentProcess(executable, arguments, _directory, _path,
                onLine: line => _dispatcher.Post(() => Receive(line)),
                onErrorLine: line => _dispatcher.Post(() => NoticeTerminalPrompt(line)),
                onExit: (status, errors) => _dispatcher.Post(() =>
                {
                    // A newer process may have replaced this one.
                    if (_process is null || ReferenceEquals(_process, started)) Exited(status, errors);
                }));
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            started = null;
        }
        _process = started;
        _lastOutput = DateTimeOffset.Now;
        _askedForTerminal = false;
        // One message per process: nothing more comes on its input. Codex and
        // Qwen wait for the input to end before they answer.
        if (Kind.Transport() == AgentTransport.PerTurn) started?.CloseInput();
    }

    private static readonly string[] TerminalPhrases =
    [
        "update available", "press enter", "press any key", "do you trust", "trust this folder", "please log in",
        "please sign in", "not logged in", "log in to", "sign in to", "login required", "run `codex login`",
        "/login", "authenticate", "[y/n]", "(y/n)", "select an option", "open the following url",
        "device code", "api key is required", "oauth session expired",
    ];

    /// <summary>Words of a screen that needs a person at the terminal.</summary>
    public static bool IsTerminalPrompt(string line)
    {
        var text = line.ToLowerInvariant();
        return TerminalPhrases.Any(text.Contains);
    }

    private void NoticeTerminalPrompt(string line)
    {
        _lastOutput = DateTimeOffset.Now;
        if (_askedForTerminal || !IsTerminalPrompt(line)) return;
        _askedForTerminal = true;
        NeedsTerminal?.Invoke(line.Trim());
    }

    private void Receive(string line)
    {
        _lastOutput = DateTimeOffset.Now;
        // Not its JSON: a screen meant for a person, maybe one that needs them.
        if (!line.TrimStart().StartsWith('{')) NoticeTerminalPrompt(line);
        foreach (var agentEvent in _parser.Parse(line))
        {
            if (agentEvent is AgentEvent.Conversation conversation)
            {
                ConversationId = conversation.Id;
                IsReady = true;
                ConversationStarted?.Invoke(conversation.Id);
                continue;
            }
            if (_current is not { } turn) continue;
            if (agentEvent is AgentEvent.TurnFinished)
            {
                FinishTurn(agentEvent);
            }
            else
            {
                turn.Reply.Apply(agentEvent, Kind);
                turn.OnUpdate(turn.Reply.Copy());
            }
        }
    }

    private void Exited(int status, string errors)
    {
        _process = null;
        IsReady = Kind.Transport() == AgentTransport.PerTurn;
        if (!IsResponding)
        {
            // Quit on its own before any message: say why.
            if (status != 0 && Kind.Transport() == AgentTransport.Persistent) StartupError = Explain(errors, status, Kind);
            return;
        }
        // Quit before finishing the turn: explain with what it printed.
        FinishTurn(new AgentEvent.Failed(Explain(errors, status, Kind)));
    }

    private void FinishTurn(AgentEvent agentEvent, bool stopped = false)
    {
        if (_current is not { } turn)
        {
            IsResponding = false;
            return;
        }
        turn.Reply.Apply(agentEvent, Kind);
        if (stopped && turn.Reply.Steps.Count == 0) turn.Reply.Error = "Detenido";
        _current = null;
        IsResponding = false;
        var reply = turn.Reply.Copy();
        turn.OnFinished(reply);
        // An error that only the CLI's screen can fix (signing in, updating).
        if (!stopped && !_askedForTerminal && reply.Error is { } error && IsTerminalPrompt(error))
        {
            _askedForTerminal = true;
            NeedsTerminal?.Invoke(error);
        }
    }

    /// <summary>The last meaningful lines of what the CLI printed on error.</summary>
    public static string Explain(string errors, int status, AgentKind agent)
    {
        var lines = errors.Split('\n')
            .Select(l => l.Trim())
            .Where(l => l.Length > 0 && !l.StartsWith("at ") && !l.Contains("node:internal"))
            .ToList();
        var line = lines.LastOrDefault(l => l.Contains("error", StringComparison.OrdinalIgnoreCase)) ?? lines.LastOrDefault();
        if (line is not null) return line.Length > 400 ? line[..400] : line;
        return $"{agent.CommandName()} se cerró (código {status}).";
    }
}
