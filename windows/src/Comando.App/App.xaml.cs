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
    private MainWindow? _window;

    public App()
    {
        InitializeComponent();
    }

    /// <summary>The app-wide owner of sessions and shells.</summary>
    public static TerminalController Controller { get; private set; } = null!;

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
                // Running unpackaged (from the debugger without deploying).
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
        catch (IOException)
        {
            // Without the script commands still run; they just don't come back as messages.
        }

        var dispatcher = new DispatcherQueueDispatcher(DispatcherQueue.GetForCurrentThread());
        Controller = new TerminalController(() => new ConPtyTerminal(), dispatcher, new SessionStore(), Version);

        _window = new MainWindow();
        _window.Activate();
    }
}
