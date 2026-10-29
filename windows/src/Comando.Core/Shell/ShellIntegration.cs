using System.Text;

namespace Comando.Core.Shell;

/// <summary>
/// Writes a PowerShell script that loads after the user's own profile and
/// reports command boundaries to the app.
/// </summary>
/// <remarks>
/// The script emits the same sequences as the zsh integration on macOS, plus
/// private OSCs for the current folder and <c>$env:PATH</c>:
/// <code>
///     OSC 133;C            command output starts   (PSConsoleHostReadLine)
///     OSC 6973;cwd;&lt;path&gt;  current folder          (prompt)
///     OSC 6973;path;&lt;PATH&gt; $env:PATH, when changed (prompt)
///     OSC 133;D;&lt;code&gt;     command finished        (prompt)
///     OSC 133;A            ready for input         (prompt)
/// </code>
/// PSReadLine has no bracketed paste, so commands arrive as
/// <c>#comando:&lt;base64&gt;</c>: a comment to PSReadLine, which the
/// PSConsoleHostReadLine wrapper decodes and hands to PowerShell as typed.
/// The script stays compatible with Windows PowerShell 5.1.
/// </remarks>
public static class ShellIntegration
{
    public const string PathOsc = "6973;path;";
    public const string DirectoryOsc = "6973;cwd;";
    public const string CommandPrefix = "#comando:";

    public static string Directory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Comando", "shell");

    public static string ScriptPath => Path.Combine(Directory, "comando.ps1");

    /// <summary>Writes the integration script. Safe to call on every launch.</summary>
    public static void Install()
    {
        System.IO.Directory.CreateDirectory(Directory);
        File.WriteAllText(ScriptPath, Script, new UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
    }

    /// <summary>The line the app types to run <paramref name="command"/>.</summary>
    public static string Encode(string command) =>
        CommandPrefix + Convert.ToBase64String(Encoding.UTF8.GetBytes(command));

    /// <summary>
    /// PowerShell 7 when it's installed, otherwise Windows PowerShell, which
    /// every Windows has.
    /// </summary>
    public static string FindShell(IEnumerable<string>? pathEntries = null)
    {
        var entries = pathEntries ?? (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator);
        foreach (var entry in entries.Where(e => e.Length > 0))
        {
            var candidate = Path.Combine(entry.Trim('"'), "pwsh.exe");
            if (File.Exists(candidate)) return candidate;
        }
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var installed = Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe");
        if (File.Exists(installed)) return installed;
        return Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");
    }

    public static bool IsPowerShell7(string shell) =>
        Path.GetFileName(shell).Equals("pwsh.exe", StringComparison.OrdinalIgnoreCase);

    /// <summary>Arguments that load the user's profile and then the integration.</summary>
    public static IReadOnlyList<string> Arguments(string scriptPath) =>
        ["-NoLogo", "-NoExit", "-ExecutionPolicy", "Bypass", "-Command", $". '{scriptPath.Replace("'", "''")}'"];

    /// <summary>Environment for a new shell, based on the app's own environment.</summary>
    public static Dictionary<string, string> BuildEnvironment(string appVersion)
    {
        var environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.DictionaryEntry entry in System.Environment.GetEnvironmentVariables())
        {
            environment[(string)entry.Key] = (string?)entry.Value ?? "";
        }
        environment["TERM"] = "xterm-256color";
        environment["COLORTERM"] = "truecolor";
        environment["TERM_PROGRAM"] = "Comando";
        environment["TERM_PROGRAM_VERSION"] = appVersion;
        // Pagers make no sense in a chat: the bubble already scrolls.
        environment["GIT_PAGER"] = "cat";
        environment["PAGER"] = "cat";
        environment["COMANDO_SHELL_INTEGRATION"] = "1";
        return environment;
    }

    private const string Script = """
        # Comando shell integration - generated, do not edit.
        if (-not $global:__ComandoInstalled) {
          $global:__ComandoInstalled = $true
          $global:__ComandoLastPath = ''
          $global:__ComandoEsc = [char]27
          $global:__ComandoBel = [char]7

          [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
          [Console]::InputEncoding = [System.Text.Encoding]::UTF8
          $global:OutputEncoding = [System.Text.Encoding]::UTF8

          function global:__ComandoOsc([string]$Payload) {
            [Console]::Write("$($global:__ComandoEsc)]$Payload$($global:__ComandoBel)")
          }

          if (-not (Get-Command PSConsoleHostReadLine -ErrorAction SilentlyContinue)) {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
          }

          try {
            # Inline predictions are drawn in a line nobody sees.
            Set-PSReadLineOption -PredictionSource None -ErrorAction Stop
          } catch { }

          # The encoded line is the app's, not the person's: keep it out of the
          # history and add the decoded command instead.
          $global:__ComandoHistoryHandler = (Get-PSReadLineOption -ErrorAction SilentlyContinue).AddToHistoryHandler
          try {
            Set-PSReadLineOption -AddToHistoryHandler {
              param([string]$Line)
              if ($Line.StartsWith('#comando:')) { return $false }
              if ($global:__ComandoHistoryHandler) { return & $global:__ComandoHistoryHandler $Line }
              return $true
            } -ErrorAction Stop
          } catch { }

          $global:__ComandoReadLine = $function:PSConsoleHostReadLine
          function global:PSConsoleHostReadLine {
            $line = & $global:__ComandoReadLine
            if ($line -and $line.StartsWith('#comando:')) {
              $line = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($line.Substring(9)))
              try { [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line) } catch { }
            }
            # A clean console for each command: a program that opens the
            # embedded terminal would otherwise repaint earlier lines.
            try { [Console]::Clear() } catch { }
            __ComandoOsc '133;C'
            $line
          }

          function global:prompt {
            $ok = $global:?
            $code = if ($ok) { 0 } elseif ($global:LASTEXITCODE) { $global:LASTEXITCODE } else { 1 }
            # Folder and PATH first, so the finished command knows where it left the shell.
            $location = $executionContext.SessionState.Path.CurrentLocation
            if ($location.Provider.Name -eq 'FileSystem') {
              __ComandoOsc "6973;cwd;$($location.ProviderPath)"
            }
            if ($env:PATH -ne $global:__ComandoLastPath) {
              $global:__ComandoLastPath = $env:PATH
              __ComandoOsc "6973;path;$($env:PATH)"
            }
            __ComandoOsc "133;D;$code"
            __ComandoOsc '133;A'
            # The app draws its own interface, so the prompt stays empty.
            "$($global:__ComandoEsc)[0m"
          }

          # Like `trash` on macOS: what the confirmation offers instead of
          # deleting for good.
          function global:papelera {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Path)
            Add-Type -AssemblyName Microsoft.VisualBasic
            foreach ($pattern in $Path) {
              foreach ($item in Get-Item -Path $pattern -Force -ErrorAction Stop) {
                if ($item.PSIsContainer) {
                  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($item.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
                } else {
                  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($item.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
                }
              }
            }
          }
        }
        """;
}
