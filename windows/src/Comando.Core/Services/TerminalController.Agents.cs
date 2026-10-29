using Comando.Core.Agents;
using Comando.Core.Models;

namespace Comando.Core.Services;

/// <summary>Conversations with AI agent CLIs, shown as chat.</summary>
public sealed partial class TerminalController
{
    private readonly Dictionary<Guid, AgentChat> _agentChats = [];

    /// <summary>Sessions whose agent conversation ends once its terminal closes.</summary>
    private readonly HashSet<Guid> _endsAgentWithTerminal = [];

    /// <summary>Bumped when a session's agent chat opens or closes, so the chat view updates.</summary>
    [CommunityToolkit.Mvvm.ComponentModel.ObservableProperty]
    public partial int AgentChatsVersion { get; private set; }

    /// <summary>
    /// The session's open conversation. One saved before quitting reopens and
    /// resumes when the next message goes out.
    /// </summary>
    public AgentChat? AgentChat(TerminalSession session)
    {
        if (_agentChats.TryGetValue(session.Id, out var chat)) return chat;
        if (AgentKinds.FromName(session.AgentName) is not { } kind) return null;
        return MakeChat(kind, session, session.AgentConversationId, session.AgentPermission);
    }

    public void StartAgent(AgentKind kind, string command, TerminalSession session, string? resuming = null)
    {
        EndAgent(session);
        var shell = Shell(session);
        var entry = new CommandEntry
        {
            Command = command,
            Directory = shell.Directory,
            Kind = EntryKind.AgentStart,
            AgentName = kind.CommandName(),
            AgentConversationId = resuming,
        };
        session.Entries.Add(entry);
        session.AgentName = kind.CommandName();
        session.AgentConversationId = resuming;
        session.AgentPermission = AgentPermission.Ask;
        session.LastActivity = entry.StartedAt;
        session.LastCommand = command;
        if (session.CustomName is null && session.AutoName is null) session.AutoName = kind.DisplayName();
        MakeChat(kind, session, resuming, AgentPermission.Ask);
        Reorder(session);
        Save();
    }

    private AgentChat MakeChat(AgentKind kind, TerminalSession session, string? conversationId, AgentPermission permission)
    {
        var shell = Shell(session);
        var chat = new AgentChat(kind, session.Id, shell.Directory, shell.PathEntries, _dispatcher, conversationId, permission);
        chat.ConversationStarted += id =>
        {
            session.AgentConversationId = id;
            // The open start card keeps it, so the conversation can be resumed.
            var start = session.Entries.LastOrDefault(e => e.Kind == EntryKind.AgentStart && e.FinishedAt is null);
            if (start is not null) start.AgentConversationId = id;
            Save();
        };
        chat.NeedsTerminal += reason => AgentNeedsTerminal(session, reason);
        _agentChats[session.Id] = chat;
        AgentChatsVersion++;
        chat.WarmUp();
        return chat;
    }

    /// <summary>Sends a message to the session's agent.</summary>
    public void SendToAgent(string text, TerminalSession session)
    {
        var message = text.Trim();
        if (message.Length == 0 || AgentChat(session) is not { IsResponding: false } chat) return;
        if (message.ToLowerInvariant() is "/salir" or "/exit" or "/quit" or "exit" or "salir")
        {
            EndAgent(session);
            return;
        }
        var shell = Shell(session);
        var name = chat.Kind.CommandName();
        var entry = new CommandEntry
        {
            Command = message,
            Directory = shell.Directory,
            Kind = EntryKind.Agent,
            AgentName = name,
            AgentReply = new AgentReply(),
        };
        session.Entries.Add(entry);
        session.LastActivity = entry.StartedAt;
        session.LastCommand = name + ": " + message;
        Reorder(session);
        Save();
        chat.Send(
            message,
            reply => entry.AgentReply = reply,
            reply =>
            {
                entry.AgentReply = reply;
                entry.FinishedAt = DateTimeOffset.Now;
                var said = reply.Text;
                session.LastCommand = name + ": " + (said.Length == 0 ? message : said.Length > 80 ? said[..80] : said);
                if (SelectedSession != session) session.UnreadCount++;
                CommandFinished?.Invoke(session, entry);
                Save();
            },
            shell.Directory,
            shell.PathEntries);
    }

    /// <summary>Lets the agent do more and asks it to try again.</summary>
    public void AllowAgent(AgentPermission permission, TerminalSession session)
    {
        if (AgentChat(session) is not { } chat) return;
        chat.Allow(permission);
        session.AgentPermission = permission;
        SendToAgent(permission == AgentPermission.Edits
            ? "Te doy permiso para crear y editar archivos. Inténtalo de nuevo."
            : "Te doy permiso para hacer lo que necesites. Inténtalo de nuevo.", session);
    }

    public void StopAgent(TerminalSession session) => AgentChat(session)?.Stop();

    public void EndAgent(TerminalSession session)
    {
        if (_agentChats.Remove(session.Id, out var chat))
        {
            chat.End();
            AgentChatsVersion++;
        }
        if (session.AgentName is null) return;
        session.AgentName = null;
        session.AgentConversationId = null;
        session.AgentPermission = AgentPermission.Ask;
        foreach (var entry in session.Entries.Where(e => e.Kind == EntryKind.AgentStart && e.FinishedAt is null))
        {
            entry.FinishedAt = DateTimeOffset.Now;
        }
        Save();
    }

    /// <summary>
    /// Continues the conversation in the CLI's own screen (to sign in, or for
    /// what doesn't fit in bubbles). When the CLI quits, the chat goes on.
    /// </summary>
    public void OpenAgentInTerminal(TerminalSession session)
    {
        if (AgentChat(session) is not { } chat || Shell(session).IsBusy) return;
        chat.Pause();
        Submit(chat.Kind.TerminalCommand(chat.ConversationId ?? session.AgentConversationId), session, confirmed: true, bypassAgentChat: true);
    }

    /// <summary>The CLI needs its own screen: say why in the chat, and open it.</summary>
    private void AgentNeedsTerminal(TerminalSession session, string reason)
    {
        if (!_agentChats.ContainsKey(session.Id) || Shell(session).IsBusy) return;
        var entry = session.Entries.Where(e => e.Kind == EntryKind.Agent).MaxBy(e => e.StartedAt);
        OpenAgentInTerminal(session);
        // After opening it, so stopping the turn doesn't write over the reason.
        if (entry?.AgentReply is { } current)
        {
            var reply = current.Copy();
            var trimmedReason = reason.Trim();
            reply.Steps.RemoveAll(step => step.Kind == AgentStepKind.Text && trimmedReason.Contains(step.Text.Trim()));
            reply.Error = reason.Length > 300 ? reason[..300] : reason;
            reply.OpenedTerminal = true;
            reply.Finish();
            entry.AgentReply = reply;
            entry.FinishedAt ??= DateTimeOffset.Now;
            Save();
        }
    }

    /// <summary>Closes the CLI's screen and goes back to chatting.</summary>
    public void ReturnToAgentChat(TerminalSession session)
    {
        _endsAgentWithTerminal.Remove(session.Id);
        _ = Shell(session).QuitForegroundAsync();
    }

    /// <summary>Closes the program in the terminal; when it's an agent's screen, the conversation ends with it.</summary>
    public void QuitProgram(TerminalSession session)
    {
        if (_agentChats.ContainsKey(session.Id)) _endsAgentWithTerminal.Add(session.Id);
        _ = Shell(session).QuitForegroundAsync();
    }

    /// <summary>Picks up a conversation that was ended, from its start card.</summary>
    public void ResumeAgent(CommandEntry entry, TerminalSession session)
    {
        if (entry.AgentKind is { } kind) StartAgent(kind, entry.Command, session, entry.AgentConversationId);
    }

    /// <summary>A command finished in a session with an agent: its screen closed, so the chat resumes or ends.</summary>
    private void AgentTerminalClosed(TerminalSession session)
    {
        if (!_agentChats.TryGetValue(session.Id, out var chat)) return;
        if (_endsAgentWithTerminal.Remove(session.Id)) EndAgent(session);
        else chat.WarmUp();
    }
}
