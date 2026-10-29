using System.Diagnostics;
using System.Text;

namespace Comando.Core.Agents;

/// <summary>
/// An agent CLI running headless: lines it prints go to <c>onLine</c>, and
/// <c>onExit</c> reports how it ended with the end of its error output.
/// Callbacks arrive on background threads.
/// </summary>
public sealed class AgentProcess : IDisposable
{
    /// <summary>Extensions Windows runs a bare program name with, in the order it tries them.</summary>
    public static readonly string[] Extensions = [".exe", ".cmd", ".bat", ".ps1"];

    private readonly Process _process;
    private readonly object _lock = new();
    private readonly StringBuilder _errorTail = new();
    private readonly Action<string> _onLine;
    private readonly Action<string> _onErrorLine;
    private readonly Action<int, string> _onExit;
    private int _openStreams = 2;
    private bool _exitReported;

    public AgentProcess(string executable, IReadOnlyList<string> arguments, string directory, IReadOnlyList<string> path,
        Action<string> onLine, Action<string>? onErrorLine, Action<int, string> onExit)
    {
        _onLine = onLine;
        _onErrorLine = onErrorLine ?? (_ => { });
        _onExit = onExit;
        var startInfo = CreateStartInfo(executable, arguments, directory, path);
        _process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        _process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is null) StreamClosed();
            else _onLine(e.Data);
        };
        _process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is null)
            {
                StreamClosed();
                return;
            }
            lock (_lock)
            {
                _errorTail.Append(e.Data).Append('\n');
                if (_errorTail.Length > 4096) _errorTail.Remove(0, _errorTail.Length - 4096);
            }
            _onErrorLine(e.Data);
        };
        _process.Exited += (_, _) => StreamClosed();
        _process.Start();
        _process.BeginOutputReadLine();
        _process.BeginErrorReadLine();
    }

    public bool IsRunning
    {
        get
        {
            try
            {
                return !_process.HasExited;
            }
            catch (InvalidOperationException)
            {
                return false;
            }
        }
    }

    /// <summary>
    /// The CLI's full path in the shell's PATH, or null when it isn't
    /// installed. npm installs agents as <c>claude.cmd</c>, so each PATH
    /// folder is tried with the extensions Windows runs.
    /// </summary>
    public static string? Executable(string name, IReadOnlyList<string> pathEntries, Func<string, bool>? exists = null)
    {
        exists ??= File.Exists;
        var folders = pathEntries.Count > 0
            ? pathEntries
            : (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);
        foreach (var folder in folders)
        {
            var trimmed = folder.Trim().Trim('"');
            if (trimmed.Length == 0) continue;
            foreach (var extension in Extensions)
            {
                var candidate = Path.Combine(trimmed, name + extension);
                if (exists(candidate)) return candidate;
            }
        }
        return null;
    }

    /// <summary>
    /// How to start <paramref name="executable"/>: batch files go through
    /// <c>cmd.exe /d /s /c</c> and PowerShell scripts through <c>pwsh -File</c>,
    /// because Windows can't start them directly with redirected streams.
    /// </summary>
    public static ProcessStartInfo CreateStartInfo(string executable, IReadOnlyList<string> arguments, string directory, IReadOnlyList<string> path)
    {
        var extension = Path.GetExtension(executable).ToLowerInvariant();
        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false),
            StandardInputEncoding = new UTF8Encoding(false),
            WorkingDirectory = System.IO.Directory.Exists(directory) ? directory : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        };
        switch (extension)
        {
            case ".cmd" or ".bat":
                startInfo.FileName = Path.Combine(Environment.SystemDirectory, "cmd.exe");
                // /s keeps the quotes of the whole line, so paths with spaces survive.
                startInfo.Arguments = "/d /s /c \"" + string.Join(' ', new[] { executable }.Concat(arguments).Select(QuoteForCmd)) + "\"";
                break;
            case ".ps1":
                startInfo.FileName = "pwsh.exe";
                startInfo.ArgumentList.Add("-NoLogo");
                startInfo.ArgumentList.Add("-NoProfile");
                startInfo.ArgumentList.Add("-ExecutionPolicy");
                startInfo.ArgumentList.Add("Bypass");
                startInfo.ArgumentList.Add("-File");
                startInfo.ArgumentList.Add(executable);
                foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
                break;
            default:
                startInfo.FileName = executable;
                foreach (var argument in arguments) startInfo.ArgumentList.Add(argument);
                break;
        }

        if (path.Count > 0) startInfo.Environment["PATH"] = string.Join(Path.PathSeparator, path);
        // Plain output: no colors or spinners meant for a terminal.
        startInfo.Environment["NO_COLOR"] = "1";
        startInfo.Environment["TERM"] = "dumb";
        startInfo.Environment.Remove("CI");
        return startInfo;
    }

    /// <summary>
    /// Quotes one word for a cmd.exe line: wrapped in double quotes when it
    /// has spaces or cmd's special characters, with inner quotes doubled.
    /// </summary>
    public static string QuoteForCmd(string argument)
    {
        if (argument.Length > 0 && argument.IndexOfAny([' ', '\t', '"', '&', '|', '<', '>', '^', '(', ')', '%', '!', ',', ';', '=']) < 0)
        {
            return argument;
        }
        return "\"" + argument.Replace("\"", "\"\"") + "\"";
    }

    public void Write(string text)
    {
        try
        {
            _process.StandardInput.Write(text);
            _process.StandardInput.Flush();
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException or ObjectDisposedException)
        {
            // It quit; onExit follows.
        }
    }

    /// <summary>No more messages: a persistent CLI finishes its turn and quits.</summary>
    public void CloseInput()
    {
        try
        {
            _process.StandardInput.Close();
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException)
        {
        }
    }

    /// <summary>Asks it to quit by closing its input, and ends it with everything it started after 2 seconds.</summary>
    public void Stop()
    {
        if (!IsRunning) return;
        CloseInput();
        var process = _process;
        _ = Task.Delay(TimeSpan.FromSeconds(2)).ContinueWith(_ =>
        {
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
            }
            catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
            }
        }, TaskScheduler.Default);
    }

    public void Dispose()
    {
        try
        {
            if (IsRunning) _process.Kill(entireProcessTree: true);
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
        }
        _process.Dispose();
    }

    /// <summary>
    /// Exit is reported once the process ended and both streams were read to
    /// the end, so no line arrives after it.
    /// </summary>
    private void StreamClosed()
    {
        int exitCode;
        string tail;
        lock (_lock)
        {
            _openStreams--;
            if (_openStreams > -1 || _exitReported) return;
            _exitReported = true;
            tail = _errorTail.ToString();
        }
        try
        {
            _process.WaitForExit();
            exitCode = _process.ExitCode;
        }
        catch (InvalidOperationException)
        {
            exitCode = -1;
        }
        _onExit(exitCode, tail);
    }
}
