using Comando.Core.Assistant;
using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Shell;

namespace Comando.Core.Services;

/// <summary>Requests in plain words, answered by the assistant, and hints for failed commands.</summary>
public sealed partial class TerminalController
{
    /// <summary>The assistant; the app gives it Phi Silica, tests a fake model.</summary>
    public AssistantEngine Assistant { get; set; } = new(NoLanguageModel.Instance);

    /// <summary>Requests the assistant is still answering.</summary>
    [CommunityToolkit.Mvvm.ComponentModel.ObservableProperty]
    public partial int AssistantRequestsInFlight { get; private set; }

    /// <summary>
    /// What the composer sends: a message to the open agent, input for the
    /// running program, a request in plain words, or a command.
    /// </summary>
    public void Send(string text, TerminalSession session, IReadOnlyList<string>? attachments = null)
    {
        attachments ??= [];
        var shell = Shell(session);
        if (!shell.IsBusy && AgentChat(session) is not null)
        {
            SendToAgent(text, session);
            return;
        }
        if (shell.IsBusy)
        {
            Submit(text, session);
            return;
        }
        if (Settings.AssistantEnabled && (attachments.Count > 0 || IntentDetector.IsPlainLanguage(text, ExecutableIndex.Names(shell.PathEntries))))
        {
            Ask(text, attachments, session);
            return;
        }
        Submit(text, session);
    }

    /// <summary>Sends a plain-language request to the assistant, with any attached files.</summary>
    public void Ask(string text, IReadOnlyList<string> attachments, TerminalSession session)
    {
        if (session.IsArchived) session.IsArchived = false;
        var request = IntentDetector.Request(text);
        if (request.Length == 0) return;
        var shell = Shell(session);
        var entry = new CommandEntry
        {
            Command = request,
            Directory = shell.Directory,
            Kind = EntryKind.Assistant,
            AttachmentPaths = [.. attachments],
            AssistantReply = new AssistantReply { IsWriting = true },
        };
        session.Entries.Add(entry);
        session.LastActivity = entry.StartedAt;
        session.LastCommand = "✨ " + request;
        Reorder(session);
        Save();
        _ = AnswerAsync(entry, session, shell);
    }

    private async Task AnswerAsync(CommandEntry entry, TerminalSession session, ShellSession shell)
    {
        AssistantRequestsInFlight++;
        try
        {
            var history = session.Entries
                .Where(e => e.Kind == EntryKind.Assistant && e.IsFinished && e != entry && e.AssistantReply is not null)
                .TakeLast(3)
                .Select(e => (e.Command, e.AssistantReply!.Explanation ?? ""))
                .ToList();
            var request = new AssistantRequest(entry.Command, entry.Directory, entry.AttachmentPaths,
                ExecutableIndex.Names(shell.PathEntries), history);
            var progress = new InlineProgress<AssistantReply>(partial => _dispatcher.Post(() =>
            {
                if (!entry.IsFinished) entry.AssistantReply = partial;
            }));
            AssistantReply reply;
            try
            {
                reply = await Assistant.AnswerAsync(request, progress);
            }
            catch (Exception)
            {
                reply = new AssistantReply { Error = "No pude responder esta vez. Inténtalo de nuevo o dilo con otras palabras." };
            }
            _dispatcher.Post(() =>
            {
                reply.IsWriting = false;
                entry.AssistantReply = reply;
                entry.FinishedAt = DateTimeOffset.Now;
                // Questions about the app aren't what the session is about.
                if (reply.Points.Count == 0 && reply.Proposals.Count > 0) NameSessionIfNeeded(session, entry.Command);
                if (SelectedSession != session) session.UnreadCount++;
                CommandFinished?.Invoke(session, entry);
                Save();
            });
        }
        finally
        {
            _dispatcher.Post(() => AssistantRequestsInFlight--);
        }
    }

    /// <summary>Runs what the assistant proposed, as one visible command.</summary>
    public void RunProposals(CommandEntry entry, TerminalSession session)
    {
        if (entry.AssistantReply is not { Proposals.Count: > 0 } reply || Shell(session).IsBusy) return;
        var command = string.Join("; ", reply.Proposals.Select(p => p.Command));
        // What the model wrote and changes things asks first, even when it's
        // no risk the detector explains.
        if (ConfirmRiskyCommands && DangerDetector.Risk(command) is null
            && reply.Proposals.Any(p => p.IsGenerated && AssistantEngine.ChangesThings(p.Command)))
        {
            _pendingProposal = entry;
            PendingCommand = new PendingCommand(command, session.Id, new CommandRisk(
                "Este comando lo escribió el asistente y cambia cosas en tu PC",
                "Revisa qué hace antes de ejecutarlo."));
            return;
        }
        Submit(command, session);
        // A risky command waits for the confirmation: “Ejecutado” only once it runs.
        if (PendingCommand is null) entry.AssistantRanAt = DateTimeOffset.Now;
        else _pendingProposal = entry;
    }

    /// <summary>Runs an install command the assistant suggested, next to its answer.</summary>
    public void RunInstall(string command, TerminalSession session) => Submit(command, IdleSession(session));

    /// <summary>Gives an unnamed session a title from its first real request.</summary>
    private void NameSessionIfNeeded(TerminalSession session, string request)
    {
        if (session.CustomName is not null || session.AutoName is not null) return;
        if (AssistantEngine.SessionTitle(request) is { } title) session.AutoName = title;
    }

    /// <summary>A failed command gets a plain-language explanation and, when there is one, a command to try.</summary>
    private static void ExplainFailure(CommandEntry entry, ShellSession shell)
    {
        if (entry.Kind != EntryKind.Command || entry.Succeeded || entry.ExitCode is null) return;
        var hint = ErrorExplainer.Hint(entry.Command, entry.PlainOutput, entry.ExitCode, () => ExecutableIndex.Names(shell.PathEntries));
        entry.HintMessage = hint?.Message;
        entry.HintSuggestion = hint?.Suggestion;
    }

    /// <summary>Reports right away on the calling thread, unlike <see cref="Progress{T}"/>.</summary>
    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}
