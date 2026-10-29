using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Terminal;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Comando.Views;

/// <summary>Small helpers for x:Bind function bindings.</summary>
public static class Formatting
{
    public static Visibility VisibleIf(bool value) => value ? Visibility.Visible : Visibility.Collapsed;

    public static Visibility VisibleIfPositive(int value) => VisibleIf(value > 0);

    public static Visibility VisibleIfText(string? value) => VisibleIf(!string.IsNullOrEmpty(value));

    public static Visibility CollapsedIfText(string? value) => VisibleIf(string.IsNullOrEmpty(value));

    public static string LastCommand(string? command) => command ?? "Sin comandos todavía";

    /// <summary>Archived sessions read quieter in the sidebar.</summary>
    public static double ArchivedOpacity(bool archived) => archived ? 0.55 : 1;

    // Avatars

    /// <summary>Avatar colors people can give a session, as in the macOS app.</summary>
    public static readonly (string Name, Color Color)[] SessionColors =
    [
        ("Gris", Color.FromArgb(255, 0x8A, 0x8B, 0x94)),
        ("Azul", Color.FromArgb(255, 0x00, 0x67, 0xC0)),
        ("Índigo", Color.FromArgb(255, 0x58, 0x56, 0xD6)),
        ("Morado", Color.FromArgb(255, 0x88, 0x4E, 0xC2)),
        ("Rosa", Color.FromArgb(255, 0xD6, 0x3A, 0x7A)),
        ("Rojo", Color.FromArgb(255, 0xC4, 0x2B, 0x1C)),
        ("Naranja", Color.FromArgb(255, 0xCA, 0x5D, 0x10)),
        ("Amarillo", Color.FromArgb(255, 0xB8, 0x86, 0x00)),
        ("Verde", Color.FromArgb(255, 0x10, 0x7C, 0x10)),
        ("Turquesa", Color.FromArgb(255, 0x00, 0x78, 0x7C)),
    ];

    public static Brush SessionBrush(int index)
    {
        var color = SessionColors[(uint)index < SessionColors.Length ? index : 0].Color;
        return new LinearGradientBrush
        {
            StartPoint = new Windows.Foundation.Point(0, 0),
            EndPoint = new Windows.Foundation.Point(0, 1),
            GradientStops =
            {
                new GradientStop { Color = Lighten(color, 0.18), Offset = 0 },
                new GradientStop { Color = color, Offset = 1 },
            },
        };
    }

    /// <summary>A Segoe Fluent Icons glyph for the session, from where it works.</summary>
    public static string SessionGlyph(string directory)
    {
        var home = FolderName.Home.TrimEnd('\\');
        var path = directory.TrimEnd('\\');
        if (path.Equals(home, StringComparison.OrdinalIgnoreCase)) return ""; // Home
        if (path.Equals(Path.Combine(home, "Desktop"), StringComparison.OrdinalIgnoreCase)) return ""; // TVMonitor
        if (path.Equals(Path.Combine(home, "Documents"), StringComparison.OrdinalIgnoreCase)) return ""; // Document
        if (path.Equals(Path.Combine(home, "Downloads"), StringComparison.OrdinalIgnoreCase)) return ""; // Download
        if (path.Length == 2 && path[1] == ':') return ""; // HardDrive
        try
        {
            bool Has(params string[] names) => names.Any(name => Path.Exists(Path.Combine(directory, name)));
            if (Has("package.json")) return ""; // Code
            if (Has("Cargo.toml", "pyproject.toml", "requirements.txt", "go.mod")) return "";
            if (Directory.EnumerateFiles(directory, "*.sln*").Any() || Directory.EnumerateFiles(directory, "*.csproj").Any()) return "";
            if (Has("Dockerfile", "compose.yaml", "docker-compose.yml")) return ""; // Package
            if (Has(".git")) return "";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
        return ""; // CommandPrompt
    }

    public static Visibility GlyphVisibility(string? emoji) => CollapsedIfText(emoji);

    // Status

    public static string Duration(TimeSpan? duration) => duration switch
    {
        null => "",
        { TotalSeconds: < 1 } => "menos de 1 s",
        { TotalSeconds: < 60 } d => $"{d.TotalSeconds:0.#} s",
        { TotalMinutes: < 60 } d => $"{(int)d.TotalMinutes} min {d.Seconds} s",
        var d => $"{(int)d.Value.TotalHours} h {d.Value.Minutes} min",
    };

    /// <summary>Ctrl+C in a Windows console ends programs with STATUS_CONTROL_C_EXIT.</summary>
    public static bool WasStopped(int? exitCode) => exitCode is -1073741510 or 130;

    // Terminal colors

    private static readonly (Color Light, Color Dark)?[] Ansi =
    [
        null,                                  // 0 black → text color
        (Hex(0xC41A16), Hex(0xFF6B63)),        // 1 red
        (Hex(0x1F8A3B), Hex(0x5FD37A)),        // 2 green
        (Hex(0x9A6B00), Hex(0xF2C84B)),        // 3 yellow
        (Hex(0x0B5FD6), Hex(0x6AA9FF)),        // 4 blue
        (Hex(0xA22EB8), Hex(0xE08BF0)),        // 5 magenta
        (Hex(0x0E7C86), Hex(0x5CD6E0)),        // 6 cyan
        null,                                  // 7 white → secondary text
        null,                                  // 8 bright black → secondary text
        (Hex(0xE02F28), Hex(0xFF8A80)),        // 9 bright red
        (Hex(0x2BA34C), Hex(0x8CEEA0)),        // 10 bright green
        (Hex(0xB38000), Hex(0xFFDE7A)),        // 11 bright yellow
        (Hex(0x2F7BF0), Hex(0x9AC5FF)),        // 12 bright blue
        (Hex(0xBF4FD4), Hex(0xF0B0FA)),        // 13 bright magenta
        (Hex(0x1296A1), Hex(0x8DECF2)),        // 14 bright cyan
        null,                                  // 15 bright white → text color
    ];

    /// <summary>The text color of the bubble, for what has to be drawn explicitly (dim or inverse text).</summary>
    public static Color TextColor(bool dark) => dark ? Colors.White : Color.FromArgb(0xE4, 0, 0, 0);

    public static Color SecondaryTextColor(bool dark) => dark ? Color.FromArgb(0xC5, 0xFF, 0xFF, 0xFF) : Color.FromArgb(0x9E, 0, 0, 0);

    /// <summary>
    /// A terminal color that stays legible on the bubble in light and dark
    /// mode. Black and white follow the text colors so they never disappear.
    /// </summary>
    public static Color TerminalColor(TermColor color, bool dark)
    {
        var text = TextColor(dark);
        var secondaryText = SecondaryTextColor(dark);
        switch (color.Kind)
        {
            case TermColorKind.Ansi:
                return AnsiColor(color.Index & 0x0F, dark, text, secondaryText);
            case TermColorKind.Palette when color.Index < 16:
                return AnsiColor(color.Index, dark, text, secondaryText);
            case TermColorKind.Palette when color.Index >= 232:
                var level = (byte)(8 + (color.Index - 232) * 10);
                return Color.FromArgb(255, level, level, level);
            case TermColorKind.Palette:
                byte[] steps = [0, 95, 135, 175, 215, 255];
                var cube = color.Index - 16;
                return Color.FromArgb(255, steps[cube / 36], steps[cube / 6 % 6], steps[cube % 6]);
            default:
                return Color.FromArgb(255, color.R, color.G, color.B);
        }
    }

    private static Color AnsiColor(int index, bool dark, Color text, Color secondaryText) => index switch
    {
        0 or 15 => text,
        7 or 8 => secondaryText,
        _ => dark ? Ansi[index]!.Value.Dark : Ansi[index]!.Value.Light,
    };

    private static Color Hex(uint rgb) => Color.FromArgb(255, (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    private static Color Lighten(Color color, double amount) => Color.FromArgb(
        color.A,
        (byte)(color.R + (255 - color.R) * amount),
        (byte)(color.G + (255 - color.G) * amount),
        (byte)(color.B + (255 - color.B) * amount));

    public static readonly Color Transparent = Colors.Transparent;
}
