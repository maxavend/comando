using System.Text;

namespace Comando.Core.Terminal;

/// <summary>The result of rendering a command's output, ready to display.</summary>
/// <param name="Preview">The tail of the output shown in the bubble, one list of runs per line.</param>
/// <param name="TotalLines">Number of lines in the whole output (after trimming).</param>
/// <param name="PreviewLines">Number of lines included in <paramref name="Preview"/>.</param>
/// <param name="PlainText">The whole output without escape sequences.</param>
/// <param name="IsTabular">
/// Output whose columns line up with spaces (ls, tables), which needs a
/// monospaced font to stay readable.
/// </param>
public sealed record RenderedOutput(
    IReadOnlyList<IReadOnlyList<StyledRun>> Preview,
    int TotalLines,
    int PreviewLines,
    string PlainText,
    bool IsTabular = false)
{
    public bool IsEmpty => TotalLines == 0;
    public bool IsClipped => PreviewLines < TotalLines;

    public static readonly RenderedOutput Empty = new([], 0, 0, "");
}

public static class OutputRenderer
{
    /// <summary>How many lines a bubble shows before offering “Mostrar todo”.</summary>
    public const int PreviewLineLimit = 300;

    /// <summary>Lines shown while a command is still streaming output.</summary>
    public const int LiveLineLimit = 80;

    public static LineBuffer Buffer(ReadOnlySpan<byte> raw, int screenRows = 40, int maxLines = 20_000)
    {
        var parser = new StreamParser();
        var buffer = new LineBuffer { ScreenRows = screenRows, MaxLines = maxLines };
        foreach (var token in parser.Feed(raw))
        {
            buffer.Apply(token.Token);
        }
        return buffer;
    }

    public static RenderedOutput Render(ReadOnlySpan<byte> raw) => Render(Buffer(raw));

    public static RenderedOutput Render(LineBuffer buffer, int previewLimit = PreviewLineLimit)
    {
        var lines = TrimmedLines(buffer);
        var start = Math.Max(0, lines.Count - previewLimit);
        var preview = new List<IReadOnlyList<StyledRun>>(lines.Count - start);
        for (var i = start; i < lines.Count; i++)
        {
            preview.Add(Runs(lines[i]));
        }
        return new RenderedOutput(
            preview,
            lines.Count + buffer.DroppedLines,
            lines.Count - start,
            JoinPlain(lines),
            IsTabular(lines));
    }

    /// <summary>
    /// Renders only the last lines of a live buffer; cheap enough to run on
    /// every update while a command streams output.
    /// </summary>
    public static RenderedOutput RenderTail(LineBuffer buffer, int limit = PreviewLineLimit)
    {
        var tail = new LineBuffer();
        tail.ReplaceLines(buffer.Lines.Skip(Math.Max(0, buffer.LineCount - (limit + 20))));
        var rendered = Render(tail, limit);
        return rendered.IsEmpty ? rendered : rendered with { TotalLines = Math.Max(rendered.TotalLines, buffer.LineCount) };
    }

    /// <summary>Plain text with escape sequences removed, used for copy and search.</summary>
    public static string PlainText(ReadOnlySpan<byte> raw) => JoinPlain(TrimmedLines(Buffer(raw)));

    /// <summary>
    /// True when text is aligned in columns: two or more spaces inside a line,
    /// or box-drawing characters. Plain sentences read better proportionally.
    /// </summary>
    public static bool IsTabular(IReadOnlyList<IReadOnlyList<Cell>> lines)
    {
        foreach (var line in lines)
        {
            var seenText = false;
            var spaces = 0;
            foreach (var cell in line)
            {
                if (cell.IsSpace)
                {
                    spaces++;
                    if (seenText && spaces >= 2) return true;
                }
                else
                {
                    var first = cell.Character[0];
                    if (first is >= '─' and <= '╿') return true;
                    seenText = true;
                    spaces = 0;
                }
            }
        }
        return false;
    }

    /// <summary>Removes trailing blank cells and leading/trailing blank lines.</summary>
    public static List<IReadOnlyList<Cell>> TrimmedLines(LineBuffer buffer)
    {
        var lines = new List<IReadOnlyList<Cell>>(buffer.LineCount);
        foreach (var line in buffer.Lines)
        {
            var end = line.Count;
            while (end > 0 && line[end - 1] is { IsSpace: true } last
                   && last.Style.Background is null && !last.Style.Has(StyleFlags.Inverse))
            {
                end--;
            }
            lines.Add(end == line.Count ? line : line.Take(end).ToList());
        }
        while (lines.Count > 0 && lines[^1].Count == 0) lines.RemoveAt(lines.Count - 1);
        while (lines.Count > 0 && lines[0].Count == 0) lines.RemoveAt(0);
        return lines;
    }

    public static List<StyledRun> Runs(IReadOnlyList<Cell> line)
    {
        var runs = new List<StyledRun>();
        var text = new StringBuilder();
        TextStyle? current = null;
        foreach (var cell in line)
        {
            if (current is { } style && style != cell.Style)
            {
                runs.Add(new StyledRun(text.ToString(), style));
                text.Clear();
            }
            current = cell.Style;
            text.Append(cell.Character);
        }
        if (current is { } last) runs.Add(new StyledRun(text.ToString(), last));
        return runs;
    }

    /// <summary>
    /// The colors to draw a style with: inverse swaps them, and bold with a
    /// standard color shows the bright variant, like most terminals.
    /// </summary>
    public static (TermColor? Foreground, TermColor? Background) EffectiveColors(TextStyle style)
    {
        var foreground = style.Foreground;
        var background = style.Background;
        if (style.Has(StyleFlags.Inverse))
        {
            (foreground, background) = (background, foreground);
        }
        if (style.Has(StyleFlags.Bold) && foreground is { Kind: TermColorKind.Ansi, Index: < 8 } ansi)
        {
            foreground = TermColor.Ansi((byte)(ansi.Index + 8));
        }
        return (foreground, background);
    }

    private static string JoinPlain(IReadOnlyList<IReadOnlyList<Cell>> lines)
    {
        var builder = new StringBuilder();
        for (var i = 0; i < lines.Count; i++)
        {
            if (i > 0) builder.Append('\n');
            foreach (var cell in lines[i]) builder.Append(cell.Character);
        }
        return builder.ToString();
    }
}
