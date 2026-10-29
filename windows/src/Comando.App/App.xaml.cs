using Comando.Core.Assistant;
using Comando.Core.Pty;
using Comando.Core.Services;
using Comando.Core.Shell;
using Comando.Services;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Windows.ApplicationModel;

namespace Comando;

public partial class App : Application
{
    public App()
    {
        InitializeComponent();
    }

    /// <summary>The app-wide owner of sessions and shells.</summary>
    public static TerminalController Controller { get; private set; } = null!;

    public static AppSettings Settings { get; private set; } = null!;

    /// <summary>Phi Silica when this PC has it.</summary>
    public static ILanguageModel Model { get; private set; } = NoLanguageModel.Instance;

    public static IDispatcher Dispatcher { get; private set; } = InlineDispatcher.Instance;

    public static NotificationService Notifications { get; } = new();

    public static MainWindow? Window { get; private set; }

    public static string Version
    {
        get
        {
            try
            {
                var version = Package.Current.Id.Version;
                return $"{version.Major}.{version.Minor}.{version.Build}";
            }
            catch (InvalidOperationException)
            {
                // Portable (unpackaged) build.
                return typeof(App).Assembly.GetName().Version?.ToString(3) ?? "0";
            }
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            ShellIntegration.Install();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Without the script commands still run; they just don't come back as messages.
        }

        Settings = AppSettings.Load();
        Dispatcher = new DispatcherQueueDispatcher(DispatcherQueue.GetForCurrentThread());
        Model = new PhiSilicaModel();
        Controller = new TerminalController(() => new ConPtyTerminal(), Dispatcher, new SessionStore(), Version)
        {
            Settings = Settings,
            Assistant = new AssistantEngine(Model),
        };
        Notifications.Register();

        Window = new MainWindow();
        Window.Activate();
    }
}
