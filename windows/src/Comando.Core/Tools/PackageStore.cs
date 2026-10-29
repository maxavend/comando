using System.Diagnostics;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using Comando.Core.Shell;

namespace Comando.Core.Tools;

/// <summary>A Node version and the npm that manages its global packages.</summary>
public sealed record NodeInstallation(string Version, string NpmPath, bool IsActive);

/// <summary>What a helper command printed.</summary>
public sealed record ProcessOutput(int ExitCode, string Output, string Errors, bool TimedOut);

/// <summary>
/// Everything installed through winget, Scoop, npm, pipx and uv, for the
/// Tools window. Lists load first; update checks, which ask the internet,
/// follow.
/// </summary>
public sealed partial class PackageStore : ObservableObject
{
    private static readonly TimeSpan ListTimeout = TimeSpan.FromSeconds(90);
    private static readonly TimeSpan UpdateTimeout = TimeSpan.FromSeconds(60);

    private readonly IDispatcher _dispatcher;
    private readonly Func<IReadOnlyList<string>> _path;
    private Task? _running;
    private bool _pending;

    /// <param name="dispatcher">Publishes results on the UI thread.</param>
    /// <param name="path">The shell's PATH entries, to find the managers it uses. Defaults to the app's PATH.</param>
    public PackageStore(IDispatcher dispatcher, Func<IReadOnlyList<string>>? path = null)
    {
        _dispatcher = dispatcher;
        _path = path ?? (() => (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries));
        Packages = [];
        AvailableManagers = [];
        NodeInstallations = [];
    }

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(OutdatedCount))]
    public partial IReadOnlyList<InstalledPackage> Packages { get; private set; }

    /// <summary>The managers installed on this PC.</summary>
    [ObservableProperty]
    public partial IReadOnlyList<PackageManager> AvailableManagers { get; private set; }

    [ObservableProperty]
    public partial IReadOnlyList<NodeInstallation> NodeInstallations { get; private set; }

    [ObservableProperty]
    public partial bool IsLoading { get; private set; }

    [ObservableProperty]
    public partial bool IsCheckingUpdates { get; private set; }

    [ObservableProperty]
    public partial bool HasLoaded { get; private set; }

    /// <summary>What went wrong in the last refresh, one line per manager.</summary>
    [ObservableProperty]
    public partial string? LastError { get; private set; }

    /// <summary>
    /// winget also lists every app installed on the PC. Only the ones it
    /// installed or recognizes (with a source) are shown unless this is on.
    /// </summary>
    public bool IncludeUnmanagedApps { get; set; }

    public int OutdatedCount => Packages.Count(p => p.IsOutdated);

    public IReadOnlyList<InstalledPackage> PackagesFor(PackageManager manager) =>
        Packages.Where(p => p.Manager == manager).ToList();

    /// <summary>
    /// Reloads everything. A refresh asked for mid-load (after an install)
    /// runs again right after the current one.
    /// </summary>
    public Task Refresh(bool checkUpdates = true)
    {
        if (_running is { IsCompleted: false } running)
        {
            _pending = true;
            return running;
        }
        _running = RunAsync(checkUpdates);
        return _running;
    }

    private async Task RunAsync(bool checkUpdates)
    {
        do
        {
            _pending = false;
            await PublishAsync(() => IsLoading = true);
            var path = _path();
            var errors = new List<string>();

            var managers = PackageManagers.All.Where(m => PathLookup.Find(m.Executable(), path) is not null).ToList();
            var nodes = await Task.Run(() => FindNodeInstallations(path));
            var lists = await Task.WhenAll(managers.Select(manager => Task.Run(() => ListAsync(manager, path, nodes, errors))));
            var packages = lists.SelectMany(list => list)
                .OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToList();

            await PublishAsync(() =>
            {
                AvailableManagers = managers;
                NodeInstallations = nodes;
                Packages = packages;
                IsLoading = false;
                HasLoaded = true;
                LastError = errors.Count == 0 ? null : string.Join('\n', errors);
            });

            if (checkUpdates && !_pending)
            {
                await PublishAsync(() => IsCheckingUpdates = true);
                var updated = await Task.Run(() => CheckUpdatesAsync(packages, managers, path, errors));
                await PublishAsync(() =>
                {
                    Packages = updated;
                    IsCheckingUpdates = false;
                    LastError = errors.Count == 0 ? null : string.Join('\n', errors);
                });
            }
        }
        while (_pending);
    }

    private async Task<List<InstalledPackage>> ListAsync(PackageManager manager, IReadOnlyList<string> path, IReadOnlyList<NodeInstallation> nodes, List<string> errors)
    {
        var executable = PathLookup.Find(manager.Executable(), path)!;
        try
        {
            switch (manager)
            {
                case PackageManager.Winget:
                    var winget = await RunAsync(executable, "list --accept-source-agreements --disable-interactivity", path, ListTimeout);
                    var installed = PackageParsers.Winget(winget.Output);
                    if (installed.Count == 0 && winget.ExitCode != 0) Report(errors, manager, winget);
                    return IncludeUnmanagedApps ? installed : installed.Where(p => !string.IsNullOrEmpty(p.Source)).ToList();

                case PackageManager.Scoop:
                    var scoop = await RunAsync(executable, "list", path, ListTimeout);
                    if (scoop.ExitCode != 0) Report(errors, manager, scoop);
                    return PackageParsers.ScoopList(scoop.Output);

                case PackageManager.Npm:
                    var all = new List<InstalledPackage>();
                    if (nodes.Count == 0)
                    {
                        var npm = await RunAsync(executable, "ls -g --depth=0 --json", path, ListTimeout);
                        all.AddRange(PackageParsers.NpmList(npm.Output));
                    }
                    foreach (var node in nodes)
                    {
                        var npm = await RunAsync(node.IsActive ? executable : node.NpmPath, "ls -g --depth=0 --json", path, ListTimeout);
                        all.AddRange(PackageParsers.NpmList(npm.Output, node.Version, node.IsActive ? null : node.NpmPath, node.IsActive));
                    }
                    return all;

                case PackageManager.Pipx:
                    var pipx = await RunAsync(executable, "list --json", path, ListTimeout);
                    if (pipx.ExitCode != 0) Report(errors, manager, pipx);
                    return PackageParsers.PipxList(pipx.Output);

                case PackageManager.Uv:
                    var uv = await RunAsync(executable, "tool list", path, ListTimeout);
                    if (uv.ExitCode != 0) Report(errors, manager, uv);
                    return PackageParsers.UvToolList(uv.Output);
            }
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
        {
            lock (errors) errors.Add($"{manager.DisplayName()}: {exception.Message}");
        }
        return [];
    }

    /// <summary>Asks for newer versions where listing didn't say (winget's list already does).</summary>
    private async Task<List<InstalledPackage>> CheckUpdatesAsync(List<InstalledPackage> packages, List<PackageManager> managers, IReadOnlyList<string> path, List<string> errors)
    {
        var latest = new Dictionary<(PackageManager, string), string>();
        try
        {
            if (managers.Contains(PackageManager.Scoop))
            {
                var status = await RunAsync(PathLookup.Find("scoop", path)!, "status", path, UpdateTimeout);
                foreach (var (name, version) in PackageParsers.ScoopStatus(status.Output)) latest[(PackageManager.Scoop, name)] = version;
            }
            if (managers.Contains(PackageManager.Npm))
            {
                // `npm outdated` exits with 1 when something is outdated, so it's read regardless.
                var outdated = await RunAsync(PathLookup.Find("npm", path)!, "outdated -g --json", path, UpdateTimeout);
                foreach (var (name, version) in PackageParsers.NpmOutdated(outdated.Output)) latest[(PackageManager.Npm, name)] = version;
            }
            if (managers.Contains(PackageManager.Uv))
            {
                var uv = await RunAsync(PathLookup.Find("uv", path)!, "tool list --outdated", path, UpdateTimeout);
                foreach (var package in PackageParsers.UvToolList(uv.Output).Where(p => p.LatestVersion is not null))
                {
                    latest[(PackageManager.Uv, package.Id)] = package.LatestVersion!;
                }
            }
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
        {
            lock (errors) errors.Add(exception.Message);
        }

        return packages.Select(package =>
            package.LatestVersion is null && package.IsActiveNode && latest.TryGetValue((package.Manager, package.Id), out var version) && version != package.Version
                ? package with { LatestVersion = version }
                : package).ToList();
    }

    private static void Report(List<string> errors, PackageManager manager, ProcessOutput output)
    {
        var line = output.TimedOut
            ? "no respondió a tiempo"
            : output.Errors.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault()
              ?? $"terminó con el código {output.ExitCode}";
        lock (errors) errors.Add($"{manager.DisplayName()}: {line}");
    }

    /// <summary>
    /// Node versions installed with nvm-windows (each has its own globals),
    /// plus the active one. Without nvm, only the active one.
    /// </summary>
    internal static List<NodeInstallation> FindNodeInstallations(IReadOnlyList<string> path)
    {
        var installations = new List<NodeInstallation>();
        var npm = PathLookup.Find("npm", path);
        if (npm is null) return installations;
        var activeVersion = PathLookup.Find("node", path) is { } node
            ? PackageParsers.NodeVersion(RunAsync(node, "--version", path, TimeSpan.FromSeconds(10)).GetAwaiter().GetResult().Output)
            : null;

        var nvmHome = Environment.GetEnvironmentVariable("NVM_HOME");
        if (!string.IsNullOrEmpty(nvmHome) && Directory.Exists(nvmHome))
        {
            foreach (var folder in Directory.EnumerateDirectories(nvmHome, "v*").OrderByDescending(f => f, StringComparer.OrdinalIgnoreCase))
            {
                var npmPath = Path.Combine(folder, "npm.cmd");
                if (!File.Exists(npmPath)) continue;
                var version = Path.GetFileName(folder)[1..];
                installations.Add(new NodeInstallation(version, npmPath, version == activeVersion));
            }
        }
        if (!installations.Any(i => i.IsActive))
        {
            installations.Insert(0, new NodeInstallation(activeVersion ?? "", npm, true));
        }
        return installations;
    }

    /// <summary>
    /// Runs a helper command without a window and returns what it printed,
    /// as UTF-8. Batch files (npm.cmd) go through cmd.exe.
    /// </summary>
    public static async Task<ProcessOutput> RunAsync(string executable, string arguments, IReadOnlyList<string> path, TimeSpan timeout)
    {
        var isBatch = executable.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || executable.EndsWith(".bat", StringComparison.OrdinalIgnoreCase);
        var info = new ProcessStartInfo
        {
            FileName = isBatch ? "cmd.exe" : executable,
            Arguments = isBatch ? $"/d /s /c \"\"{executable}\" {arguments}\"" : arguments,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        info.Environment["PATH"] = string.Join(Path.PathSeparator, path);
        // Plain output: no colors or spinners meant for a terminal.
        info.Environment["NO_COLOR"] = "1";
        info.Environment["PYTHONIOENCODING"] = "utf-8";

        using var process = Process.Start(info) ?? throw new InvalidOperationException($"No se pudo abrir {Path.GetFileName(executable)}.");
        process.StandardInput.Close();
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        using var cancellation = new CancellationTokenSource(timeout);
        var timedOut = false;
        try
        {
            await process.WaitForExitAsync(cancellation.Token);
        }
        catch (OperationCanceledException)
        {
            timedOut = true;
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
            }
        }
        return new ProcessOutput(timedOut ? -1 : process.ExitCode, await output, await errors, timedOut);
    }

    private Task PublishAsync(Action action)
    {
        var done = new TaskCompletionSource();
        _dispatcher.Post(() =>
        {
            try
            {
                action();
            }
            finally
            {
                done.SetResult();
            }
        });
        return done.Task;
    }
}

/// <summary>Finds programs on a PATH the way Windows does: with .exe, .cmd, .bat or .com.</summary>
public static class PathLookup
{
    private static readonly string[] Extensions = [".exe", ".cmd", ".bat", ".com"];

    public static string? Find(string name, IReadOnlyList<string> path)
    {
        foreach (var entry in path)
        {
            var folder = entry.Trim().Trim('"');
            if (folder.Length == 0) continue;
            try
            {
                if (Path.HasExtension(name) && File.Exists(Path.Combine(folder, name))) return Path.Combine(folder, name);
                foreach (var extension in Extensions)
                {
                    var candidate = Path.Combine(folder, name + extension);
                    if (File.Exists(candidate)) return candidate;
                }
            }
            catch (ArgumentException)
            {
                // A PATH entry with characters Windows doesn't allow.
            }
        }
        return null;
    }
}
