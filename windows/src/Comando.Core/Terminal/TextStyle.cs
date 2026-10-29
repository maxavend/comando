namespace Comando.Core.Terminal;

public enum TermColorKind : byte
{
    /// <summary>One of the 16 standard ANSI colors (0–7 normal, 8–15 bright).</summary>
    Ansi,
    /// <summary>xterm 256-color palette index (16–255).</summary>
    Palette,
    Rgb,
}

public readonly record struct TermColor(TermColorKind Kind, byte Index, byte R = 0, byte G = 0, byte B = 0)
{
    public static TermColor Ansi(byte index) => new(TermColorKind.Ansi, index);
    public static TermColor Palette(byte index) => new(TermColorKind.Palette, index);
    public static TermColor Rgb(byte r, byte g, byte b) => new(TermColorKind.Rgb, 0, r, g, b);
}

[Flags]
public enum StyleFlags : byte
{
    None = 0,
    Bold = 1 << 0,
    Dim = 1 << 1,
    Italic = 1 << 2,
    Underline = 1 << 3,
    Inverse = 1 << 4,
    Strikethrough = 1 << 5,
}

public readonly record struct TextStyle(TermColor? Foreground = null, TermColor? Background = null, StyleFlags Flags = StyleFlags.None)
{
    public static readonly TextStyle Plain = new();

    public bool IsPlain => this == Plain;

    public bool Has(StyleFlags flag) => (Flags & flag) != 0;

    /// <summary>Erased cells keep the current background color but nothing else.</summary>
    internal TextStyle BackgroundOnly => new(null, Background, StyleFlags.None);
}

/// <summary>One character on screen. <see cref="Character"/> is a whole grapheme (an emoji with modifiers is one cell).</summary>
public readonly record struct Cell(string Character, TextStyle Style)
{
    public static readonly Cell Blank = new(" ", TextStyle.Plain);

    public bool IsSpace => Character == " ";
}

/// <summary>A run of characters sharing one style.</summary>
public sealed record StyledRun(string Text, TextStyle Style);
