using System.ComponentModel;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;

namespace Comando.Core.Services;

public enum AppTheme
{
    System,
    Light,
    Dark,
}

/// <summary>
/// The person's preferences, kept in a JSON file next to the history so they
/// work the same whether the app is installed (MSIX) or portable.
/// </summary>
public sealed partial class AppSettings : ObservableObject
{
    public const string DefaultInteractiveCommands =
        "ssh python py python3 ipython node bun deno pwsh powershell cmd wsl mysql psql sqlite3 redis-cli mongosh ftp sftp telnet nslookup vim nvim nano edit less htop btop";

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };
    private string? _path;

    public AppSettings()
    {
        FontSize = 13;
        NotifyAfterSeconds = 10;
        InteractiveCommandsText = DefaultInteractiveCommands;
        ConfirmRiskyCommands = true;
        AssistantEnabled = true;
        SearchesToolsOnline = true;
        AgentsAsChat = true;
        Theme = AppTheme.System;
    }

    /// <summary>Size of the terminal text in bubbles and the composer.</summary>
    [ObservableProperty]
    public partial double FontSize { get; set; }

    /// <summary>Commands that take longer than this notify when they finish while the window isn't in front.</summary>
    [ObservableProperty]
    public partial double NotifyAfterSeconds { get; set; }

    /// <summary>First words that open the embedded terminal right away, separated by spaces.</summary>
    [ObservableProperty]
    public partial string InteractiveCommandsText { get; set; }

    /// <summary>Ask before commands that are hard to undo.</summary>
    [ObservableProperty]
    public partial bool ConfirmRiskyCommands { get; set; }

    [ObservableProperty]
    public partial bool HasSeenWelcome { get; set; }

    /// <summary>Plain-language requests go to the assistant.</summary>
    [ObservableProperty]
    public partial bool AssistantEnabled { get; set; }

    /// <summary>The assistant may search winget and npm by keyword to suggest tools.</summary>
    [ObservableProperty]
    public partial bool SearchesToolsOnline { get; set; }

    /// <summary>AI agent CLIs open as a chat, with their answers in bubbles.</summary>
    [ObservableProperty]
    public partial bool AgentsAsChat { get; set; }

    [ObservableProperty]
    public partial AppTheme Theme { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public IReadOnlySet<string> InteractiveCommands => new HashSet<string>(
        InteractiveCommandsText.Split([' ', ',', '\n', '\r', '\t'], StringSplitOptions.RemoveEmptyEntries),
        StringComparer.OrdinalIgnoreCase);

    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Comando", "settings.json");

    /// <summary>Reads the settings, and saves them again whenever one changes.</summary>
    public static AppSettings Load(string? path = null)
    {
        path ??= DefaultPath;
        AppSettings settings;
        try
        {
            settings = File.Exists(path)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path), Options) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            settings = new AppSettings();
        }
        settings._path = path;
        settings.PropertyChanged += OnChanged;
        return settings;
    }

    private static void OnChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (sender is AppSettings settings) settings.Save();
    }

    public void Save()
    {
        if (_path is null) return;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            File.WriteAllText(_path, JsonSerializer.Serialize(this, Options));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }
}
