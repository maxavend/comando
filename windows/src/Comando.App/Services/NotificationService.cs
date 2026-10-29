using Comando.Core.Agents;
using Comando.Core.Models;
using Comando.Views;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Comando.Services;

/// <summary>
/// Tells the person when a long command finishes while they're elsewhere;
/// clicking the notification opens its session.
/// </summary>
public sealed class NotificationService
{
    private bool _registered;

    /// <summary>Called on the UI thread with the session to open.</summary>
    public event Action<Guid>? SessionRequested;

    public void Register()
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += OnInvoked;
            AppNotificationManager.Default.Register();
            _registered = true;
        }
        catch (Exception)
        {
            // Notifications aren't available (an unusual install); commands still work.
        }
    }

    public void Unregister()
    {
        if (!_registered) return;
        try
        {
            AppNotificationManager.Default.Unregister();
        }
        catch (Exception)
        {
        }
    }

    /// <summary>Notifies when the command took long enough and the person isn't looking at it.</summary>
    public void CommandFinished(TerminalSession session, CommandEntry entry, bool windowActive, bool sessionSelected)
    {
        var threshold = App.Settings.NotifyAfterSeconds;
        if (!_registered || threshold <= 0 || entry.Duration is not { } duration || duration.TotalSeconds < threshold) return;
        if (windowActive && sessionSelected) return;

        var failed = entry.Kind == EntryKind.Command && !entry.Succeeded && !Formatting.WasStopped(entry.ExitCode);
        var title = entry.Kind switch
        {
            EntryKind.Agent => $"{entry.AgentKind?.DisplayName() ?? "El agente"} respondió",
            EntryKind.Assistant => "El asistente respondió",
            _ => failed ? "El comando falló" : "Comando terminado",
        };
        var body = failed
            ? $"{entry.Command} · código {entry.ExitCode} · {Formatting.Duration(duration)}"
            : $"{entry.Command} · {Formatting.Duration(duration)}";
        try
        {
            var notification = new AppNotificationBuilder()
                .AddArgument("session", session.Id.ToString())
                .AddText(title)
                .AddText(session.DisplayName)
                .AddText(body)
                .BuildNotification();
            AppNotificationManager.Default.Show(notification);
        }
        catch (Exception)
        {
        }
    }

    private void OnInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
    {
        if (args.Arguments.TryGetValue("session", out var value) && Guid.TryParse(value, out var id))
        {
            App.Dispatcher.Post(() => SessionRequested?.Invoke(id));
        }
    }
}
