using System.Text;
using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Pty;
using Comando.Core.Services;
using Comando.Core.Shell;
using Comando.Core.Terminal;

namespace Comando.Core.Tests;

/// <summary>Stands in for ConPTY: records what the app types and plays back what PowerShell would print.</summary>
internal sealed class FakeTerminal : IPseudoTerminal
{
    public event Action<byte[]>? DataReceived;
    public event Action<int?>? Exited;

    public bool IsRunning { get; private set; }
    public PtyStartInfo? StartInfo { get; private set; }
    public List<string> Written { get; } = [];

    public void Start(PtyStartInfo info)
    {
        StartInfo = info;
        IsRunning = true;
    }

    public void Write(ReadOnlySpan<byte> bytes) => Written.Add(Encoding.UTF8.GetString(bytes));

    public void Resize(int columns, int rows) { }

    public void Print(string text) => DataReceived?.Invoke(Encoding.UTF8.GetBytes(text));

    public void Exit(int code)
    {
        IsRunning = false;
        Exited?.Invoke(code);
    }

    public void Dispose() => IsRunning = false;

    public static string Osc(string payload) => $"\u001B]{payload}\u0007";

    /// <summary>What the integration prints when a prompt is ready.</summary>
    public void Prompt(int code, string directory) =>
        Print(Osc($"133;D;{code}") + Osc($"6973;cwd;{directory}") + Osc("133;A") + "\u001B[0m");
}

public class ShellSessionTests
{
    private static (ShellSession Shell, FakeTerminal Terminal) Started()
    {
        var terminal = new FakeTerminal();
        var shell = new ShellSession(Guid.NewGuid(), Path.GetTempPath(), () => terminal, InlineDispatcher.Instance);
        shell.Start();
        terminal.Prompt(0, @"C:\Users\max");
        return (shell, terminal);
    }

    [Fact]
    public void BecomesIdleAtFirstPrompt()
    {
        var (shell, _) = Started();
        Assert.Equal(ShellPhase.Idle, shell.Phase);
        Assert.Equal(@"C:\Users\max", shell.Directory);
    }

    [Fact]
    public void CommandsAreSentEncoded()
    {
        var (shell, terminal) = Started();
        shell.Run("Get-ChildItem\n| Select -First 1", Guid.NewGuid());
        var line = Assert.Single(terminal.Written);
        Assert.StartsWith(ShellIntegration.CommandPrefix, line);
        Assert.EndsWith("\r", line);
        var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(line[ShellIntegration.CommandPrefix.Length..^1]));
        Assert.Equal("Get-ChildItem\n| Select -First 1", decoded);
    }

    [Fact]
    public void OutputBetweenStartAndFinishBecomesTheResult()
    {
        var (shell, terminal) = Started();
        CommandResult? result = null;
        shell.Finished += (_, r) => result = r;
        var id = Guid.NewGuid();
        shell.Run("git status", id);
        Assert.Equal(ShellPhase.Running, shell.Phase);

        // PSReadLine echoes the typed line before the command starts; it's not output.
        terminal.Print("#comando:Z2l0IHN0YXR1cw==\r\n" + FakeTerminal.Osc("133;C") + "On branch main\r\n");
        terminal.Prompt(0, @"C:\Users\max");

        Assert.NotNull(result);
        Assert.Equal(id, result.EntryId);
        Assert.Equal(0, result.ExitCode);
        Assert.Equal("On branch main", OutputRenderer.PlainText(result.Output));
        Assert.Equal(ShellPhase.Idle, shell.Phase);
    }

    [Fact]
    public void FolderChangesAreReported()
    {
        var (shell, terminal) = Started();
        string? moved = null;
        shell.DirectoryChanged += (_, directory) => moved = directory;
        shell.Run("cd D:\\Proyectos", Guid.NewGuid());
        terminal.Print(FakeTerminal.Osc("133;C"));
        terminal.Prompt(0, @"D:\Proyectos");
        Assert.Equal(@"D:\Proyectos", moved);
    }

    [Fact]
    public void PathIsSplitBySemicolons()
    {
        var (shell, terminal) = Started();
        terminal.Print(FakeTerminal.Osc(@"6973;path;C:\Windows;C:\Program Files\Git\cmd"));
        Assert.Equal(new[] { @"C:\Windows", @"C:\Program Files\Git\cmd" }, shell.PathEntries);
    }

    [Fact]
    public void AlternateScreenOpensTheTerminal()
    {
        var (shell, terminal) = Started();
        shell.Run("edit notas.txt", Guid.NewGuid());
        terminal.Print(FakeTerminal.Osc("133;C") + "\u001B[?1049h");
        Assert.Equal(ShellPhase.Interactive, shell.Phase);
    }

    [Fact]
    public void CommandsWaitForTheFirstPrompt()
    {
        var terminal = new FakeTerminal();
        var shell = new ShellSession(Guid.NewGuid(), Path.GetTempPath(), () => terminal, InlineDispatcher.Instance);
        shell.Run("dir", Guid.NewGuid());
        Assert.Empty(terminal.Written);
        terminal.Prompt(0, @"C:\");
        Assert.Single(terminal.Written);
        Assert.Equal(ShellPhase.Running, shell.Phase);
    }

    [Fact]
    public void FirstWordDropsPathAndExtension()
    {
        Assert.Equal("git", ShellSession.FirstWord(@"C:\tools\git.exe status"));
        Assert.Equal("claude", ShellSession.FirstWord("  claude --resume"));
    }

    [Fact]
    public void AgentsAreRecognized()
    {
        Assert.True(AICommandLine.IsAgent("claude"));
        Assert.True(AICommandLine.IsAgent("npx @openai/codex"));
        Assert.True(AICommandLine.IsAgent("ollama run llama3"));
        Assert.False(AICommandLine.IsAgent("ollama list"));
        Assert.False(AICommandLine.IsAgent("git status"));
    }
}

public class ControllerTests
{
    private static TerminalController Controller(out List<FakeTerminal> terminals)
    {
        var created = new List<FakeTerminal>();
        terminals = created;
        var store = new SessionStore(Path.Combine(Path.GetTempPath(), $"comando-{Guid.NewGuid()}.json"));
        return new TerminalController(() =>
        {
            var terminal = new FakeTerminal();
            created.Add(terminal);
            return terminal;
        }, InlineDispatcher.Instance, store);
    }

    [Fact]
    public void RiskyCommandsWaitForConfirmation()
    {
        var controller = Controller(out var terminals);
        var session = controller.SelectedSession!;
        controller.Submit("Remove-Item build -Recurse -Force", session);
        Assert.NotNull(controller.PendingCommand);
        Assert.Equal("papelera build", controller.PendingCommand.RecycleBinAlternative);
        Assert.Empty(session.Entries);
    }

    [Fact]
    public void RecycleBinAlternativeRunsInstead()
    {
        var controller = Controller(out var terminals);
        var session = controller.SelectedSession!;
        controller.Shell(session);
        terminals[0].Prompt(0, @"C:\Users\max");
        controller.Submit("del notas.txt", session);
        controller.SendToRecycleBinInstead();
        var entry = Assert.Single(session.Entries);
        Assert.Equal("papelera notas.txt", entry.Command);
    }

    [Fact]
    public void FinishedCommandsKeepTheirOutput()
    {
        var controller = Controller(out var terminals);
        var session = controller.SelectedSession!;
        controller.Shell(session);
        terminals[0].Prompt(0, @"C:\Users\max");
        controller.Submit("echo hola", session);
        terminals[0].Print(FakeTerminal.Osc("133;C") + "hola\r\n");
        terminals[0].Prompt(0, @"C:\Users\max");
        var entry = Assert.Single(session.Entries);
        Assert.Equal("hola", entry.PlainOutput);
        Assert.True(entry.Succeeded);
        Assert.True(entry.IsFinished);
    }

    [Fact]
    public void ClsClearsTheChat()
    {
        var controller = Controller(out var terminals);
        var session = controller.SelectedSession!;
        session.Entries.Add(new CommandEntry { Command = "dir" });
        controller.Submit("cls", session);
        Assert.Empty(session.Entries);
    }
}

public class LanguageTests
{
    [Theory]
    [InlineData("Remove-Item C:\\temp -Recurse")]
    [InlineData("rm -rf node_modules")]
    [InlineData("del *.log")]
    [InlineData("rd /s /q build")]
    [InlineData("irm https://example.com/install.ps1 | iex")]
    [InlineData("iex (irm https://example.com/install.ps1)")]
    [InlineData("git reset --hard HEAD~1")]
    [InlineData("git push --force")]
    [InlineData("Stop-Computer")]
    [InlineData("taskkill /f /im node.exe")]
    [InlineData("Format-Volume -DriveLetter E")]
    [InlineData("Get-ChildItem *.jpg | Rename-Item -NewName { $_.Name -replace 'IMG','foto' }")]
    [InlineData("Start-Process pwsh -Verb RunAs")]
    [InlineData("cd build; Remove-Item * -Recurse")]
    [InlineData("Get-ChildItem | % { Remove-Item $_ -Recurse }")]
    public void RiskyCommands(string command) => Assert.NotNull(DangerDetector.Risk(command));

    [Theory]
    [InlineData("Get-ChildItem")]
    [InlineData("Remove-Item notas.txt -Force")]
    [InlineData("git status")]
    [InlineData("shutdown /a")]
    [InlineData("npm install")]
    [InlineData("winget upgrade --all")]
    public void SafeCommands(string command) => Assert.Null(DangerDetector.Risk(command));

    [Theory]
    [InlineData("Remove-Item -Recurse build", "papelera build")]
    [InlineData("rm -rf \"mis fotos\" otra", "papelera 'mis fotos' otra")]
    [InlineData("del /q notas.txt", "papelera notas.txt")]
    [InlineData("Remove-Item -Path C:\\temp\\x -Force", "papelera C:\\temp\\x")]
    public void DeletesBecomeRecycleBin(string command, string expected) =>
        Assert.Equal(expected, RecycleBinConverter.Command(command));

    [Theory]
    [InlineData("Get-ChildItem | Remove-Item")]
    [InlineData("Remove-Item -Filter *.tmp")]
    [InlineData("rm")]
    [InlineData("git rm archivo")]
    public void OtherCommandsStayAsTheyAre(string command) => Assert.Null(RecycleBinConverter.Command(command));

    [Fact]
    public void WordsRespectQuotesAndBackticks()
    {
        Assert.Equal(new[] { "Remove-Item", "mis fotos", "-Force" }, ShellWords.Split("Remove-Item \"mis fotos\" -Force"));
        Assert.Equal(new[] { "echo", "a b" }, ShellWords.Split("echo a` b"));
        Assert.Equal(new[] { "git", "commit", "-m", "primer cambio" }, ShellWords.Split("git commit -m 'primer cambio'"));
    }

    [Fact]
    public void FolderNames()
    {
        var home = FolderName.Home;
        Assert.Equal("Inicio", FolderName.Display(home));
        Assert.Equal("Proyectos", FolderName.Display(@"D:\Proyectos"));
        Assert.Equal("Disco D:", FolderName.Display(@"D:\"));
    }
}

public class ConPtyTests
{
    [Fact]
    public void ArgumentsAreQuotedForWindows()
    {
        Assert.Equal("pwsh.exe", WindowsCommandLine.Quote("pwsh.exe"));
        Assert.Equal("\"C:\\Program Files\\PowerShell\\7\\pwsh.exe\"", WindowsCommandLine.Quote(@"C:\Program Files\PowerShell\7\pwsh.exe"));
        Assert.Equal("\"say \\\"hi\\\"\"", WindowsCommandLine.Quote("say \"hi\""));
        Assert.Equal("\"C:\\dir with space\\\\\"", WindowsCommandLine.Quote(@"C:\dir with space\"));
        Assert.Equal("\"\"", WindowsCommandLine.Quote(""));
    }

    [Fact]
    public void EnvironmentBlockIsSortedAndDoubleTerminated()
    {
        var block = WindowsCommandLine.EnvironmentBlock(new Dictionary<string, string> { ["b"] = "2", ["A"] = "1" });
        Assert.Equal("A=1\0b=2\0\0", block);
    }
}
