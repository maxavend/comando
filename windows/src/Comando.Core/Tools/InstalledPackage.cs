using Comando.Core.Language;

namespace Comando.Core.Tools;

/// <summary>The package managers the Tools window knows on Windows.</summary>
public enum PackageManager
{
    Winget,
    Scoop,
    Npm,
    Pipx,
    Uv,
}

/// <summary>Something installed by a package manager.</summary>
/// <param name="Manager">Who installed it.</param>
/// <param name="Name">The name people see.</param>
/// <param name="Id">What the manager calls it in its commands (a winget id, an npm package name).</param>
/// <param name="Version">The installed version.</param>
/// <param name="LatestVersion">The newest version, when known.</param>
public sealed record InstalledPackage(
    PackageManager Manager,
    string Name,
    string Id,
    string Version,
    string? LatestVersion = null)
{
    /// <summary>A newer version is known.</summary>
    public bool IsOutdated => !string.IsNullOrEmpty(LatestVersion) && LatestVersion != Version;

    /// <summary>For winget: the source it came from (<c>winget</c>, <c>msstore</c>), empty for apps winget only sees installed.</summary>
    public string? Source { get; init; }

    /// <summary>winget cut the id to fit its table; commands then match it by prefix instead of exactly.</summary>
    public bool IsIdTruncated { get; init; }

    /// <summary>Commands it adds to the shell.</summary>
    public IReadOnlyList<string> Commands { get; init; } = [];

    /// <summary>For npm: the Node version it belongs to (each has its own globals).</summary>
    public string? NodeVersion { get; init; }

    /// <summary>For npm under another Node version: that version's npm.cmd.</summary>
    public string? NpmPath { get; init; }

    public bool IsActiveNode { get; init; } = true;

    /// <summary>A stable key for lists.</summary>
    public string Key => $"{Manager}:{NodeVersion}:{Id}";

    /// <summary>Where it came from, in a few words (“npm global · Node 20.11.0”).</summary>
    public string Origin => NodeVersion is null ? Manager.DisplayName() : $"{Manager.DisplayName()} · Node {NodeVersion}";

    public string UpgradeCommand => Manager.UpgradeCommand(this);

    public string UninstallCommand => Manager.UninstallCommand(this);
}

/// <summary>Names, icons and the PowerShell commands of each manager.</summary>
/// <remarks>The commands run visibly in a session, so the person sees what they print.</remarks>
public static class PackageManagers
{
    public static readonly IReadOnlyList<PackageManager> All =
        [PackageManager.Winget, PackageManager.Scoop, PackageManager.Npm, PackageManager.Pipx, PackageManager.Uv];

    private const string WingetAgreements = "--accept-source-agreements --accept-package-agreements";

    public static string DisplayName(this PackageManager manager) => manager switch
    {
        PackageManager.Winget => "winget",
        PackageManager.Scoop => "Scoop",
        PackageManager.Npm => "npm global",
        PackageManager.Pipx => "pipx",
        PackageManager.Uv => "uv",
        _ => manager.ToString(),
    };

    /// <summary>A Segoe Fluent Icons glyph.</summary>
    public static string Glyph(this PackageManager manager) => manager switch
    {
        PackageManager.Winget => "", // Package
        PackageManager.Scoop => "",  // Download
        _ => "",                     // Code
    };

    /// <summary>The program that runs the manager.</summary>
    public static string Executable(this PackageManager manager) => manager switch
    {
        PackageManager.Winget => "winget",
        PackageManager.Scoop => "scoop",
        PackageManager.Npm => "npm",
        PackageManager.Pipx => "pipx",
        PackageManager.Uv => "uv",
        _ => manager.ToString().ToLowerInvariant(),
    };

    public static string UpgradeCommand(this PackageManager manager, InstalledPackage package) => manager switch
    {
        PackageManager.Winget => $"winget upgrade {WingetTarget(package)} {WingetAgreements}",
        PackageManager.Scoop => $"scoop update {Q(package.Id)}",
        PackageManager.Npm => NpmPrefix(package) + $"install -g {Q(package.Id + "@latest")}",
        PackageManager.Pipx => $"pipx upgrade {Q(package.Id)}",
        PackageManager.Uv => $"uv tool upgrade {Q(package.Id)}",
        _ => "",
    };

    public static string UpgradeAllCommand(this PackageManager manager) => manager switch
    {
        PackageManager.Winget => $"winget upgrade --all {WingetAgreements}",
        PackageManager.Scoop => "scoop update '*'",
        PackageManager.Npm => "npm update -g",
        PackageManager.Pipx => "pipx upgrade-all",
        PackageManager.Uv => "uv tool upgrade --all",
        _ => "",
    };

    public static string UninstallCommand(this PackageManager manager, InstalledPackage package) => manager switch
    {
        PackageManager.Winget => $"winget uninstall {WingetTarget(package)} --accept-source-agreements",
        PackageManager.Scoop => $"scoop uninstall {Q(package.Id)}",
        PackageManager.Npm => NpmPrefix(package) + $"uninstall -g {Q(package.Id)}",
        PackageManager.Pipx => $"pipx uninstall {Q(package.Id)}",
        PackageManager.Uv => $"uv tool uninstall {Q(package.Id)}",
        _ => "",
    };

    public static string InstallCommand(this PackageManager manager, string id) => manager switch
    {
        PackageManager.Winget => $"winget install --id {Q(id)} --exact --source winget {WingetAgreements}",
        PackageManager.Scoop => $"scoop install {Q(id)}",
        PackageManager.Npm => $"npm install -g {Q(id)}",
        PackageManager.Pipx => $"pipx install {Q(id)}",
        PackageManager.Uv => $"uv tool install {Q(id)}",
        _ => "",
    };

    private static string WingetTarget(InstalledPackage package) =>
        package.IsIdTruncated ? $"--id {Q(package.Id)}" : $"--id {Q(package.Id)} --exact";

    /// <summary>Globals of another Node version go through that version's own npm.</summary>
    private static string NpmPrefix(InstalledPackage package) =>
        !package.IsActiveNode && package.NpmPath is { } npm ? $"& {Q(npm)} " : "npm ";

    private static string Q(string value) => ShellWords.Quote(value);
}
