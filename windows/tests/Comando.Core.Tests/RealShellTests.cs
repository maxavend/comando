using System.Collections.Concurrent;
using System.Runtime.Versioning;
using Comando.Core.Pty;
using Comando.Core.Shell;
using Comando.Core.Terminal;

namespace Comando.Core.Tests;

/// <summary>Runs every posted action on one thread, in order, like the UI thread.</summary>
internal sealed class SerialDispatcher : IDispatcher, IDisposable
{
    private readonly BlockingCollection<Action> _queue = [];
    private readonly Thread _thread;

    public SerialDispatcher()
    {
        _thread = new Thread(() =>
        {
            foreach (var action in _queue.GetConsumingEnumerable()) action();
        }) { IsBackground = true };
        _thread.Start();
    }

    public void Post(Action action)
    {
        if (!_queue.IsAddingCompleted) _queue.Add(action);
    }

    public void Dispose() => _queue.CompleteAdding();
}

/// <summary>
/// The real thing on Windows: PowerShell in a pseudoconsole with the shell
/// integration. Skipped on other systems.
/// </summary>
public class RealShellTests
{
    private static async Task<(CommandResult Result, string Directory)> Run(string command)
    {
        ShellIntegration.Install();
        using var dispatcher = new SerialDispatcher();
        var finished = new TaskCompletionSource<(CommandResult, string)>(TaskCreationOptions.RunContinuationsAsynchronously);
        ShellSession? shell = null;
        dispatcher.Post(() =>
        {
            shell = new ShellSession(Guid.NewGuid(), Path.GetTempPath(), Create, dispatcher);
            shell.Finished += (session, result) => finished.TrySetResult((result, session.Directory));
            shell.Run(command, Guid.NewGuid());
        });
        try
        {
            return await finished.Task.WaitAsync(TimeSpan.FromSeconds(90));
        }
        finally
        {
            dispatcher.Post(() => shell?.Dispose());
        }
    }

    [SupportedOSPlatform("windows10.0.17763")]
    private static IPseudoTerminal CreateConPty() => new ConPtyTerminal();

    private static IPseudoTerminal Create() =>
        OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763) ? CreateConPty() : throw new PlatformNotSupportedException();

    [Fact]
    public async Task OutputComesBackAsTheCommandsResult()
    {
        if (!OperatingSystem.IsWindows()) return;
        var (result, _) = await Run("Write-Output hola; 1..3 | ForEach-Object { \"línea $_\" }");
        Assert.Equal(0, result.ExitCode);
        Assert.Equal("hola\nlínea 1\nlínea 2\nlínea 3", OutputRenderer.PlainText(result.Output));
    }

    [Fact]
    public async Task ExitCodesOfProgramsAreKept()
    {
        if (!OperatingSystem.IsWindows()) return;
        var (result, _) = await Run("cmd /c exit 3");
        Assert.Equal(3, result.ExitCode);
    }

    [Fact]
    public async Task MultiLineCommandsRunWhole()
    {
        if (!OperatingSystem.IsWindows()) return;
        var (result, _) = await Run("$a = 2\n$b = 3\nWrite-Output ($a * $b)");
        Assert.Equal("6", OutputRenderer.PlainText(result.Output));
    }

    [Fact]
    public async Task FolderChangesAreReported()
    {
        if (!OperatingSystem.IsWindows()) return;
        var target = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var (_, directory) = await Run($"Set-Location -LiteralPath '{target}'");
        Assert.Equal(target.TrimEnd('\\'), directory.TrimEnd('\\'), ignoreCase: true);
    }

    [Fact]
    public async Task ErrorsFailTheCommand()
    {
        if (!OperatingSystem.IsWindows()) return;
        var (result, _) = await Run("Get-Item C:\\no-existe-esta-carpeta");
        Assert.NotEqual(0, result.ExitCode);
    }
}
