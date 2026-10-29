using System.Globalization;

namespace Comando.Core.Terminal;

/// <summary>
/// A minimal line-oriented terminal model used to render command output as
/// chat bubbles.
/// </summary>
/// <remarks>
/// It is not a full emulator: it understands what commands typically print
/// when they are not full-screen programs — colors, carriage-return progress
/// bars, cursor movement within recent lines, erase sequences and man-page
/// style overstrike — and ignores the rest.
/// </remarks>
public sealed class LineBuffer
{
    private List<List<Cell>> _lines = [[]];
    private (int Row, int Column)? _savedCursor;
    private bool _pendingOverstrike;

    public IReadOnlyList<IReadOnlyList<Cell>> Lines => _lines;
    public int Row { get; private set; }
    public int Column { get; private set; }
    public int DroppedLines { get; private set; }
    public TextStyle Style { get; set; }

    /// <summary>Rows of the virtual screen; used to resolve absolute cursor positioning.</summary>
    public int ScreenRows { get; set; } = 40;

    public int MaxLines { get; set; } = 20_000;

    public int LineCount => _lines.Count;

    public bool IsEmpty => _lines.All(line => line.All(cell => cell.IsSpace));

    public void Apply(TerminalToken token)
    {
        switch (token)
        {
            case TerminalToken.Text text:
                var elements = StringInfo.GetTextElementEnumerator(text.Value);
                while (elements.MoveNext())
                {
                    Write(elements.GetTextElement());
                }
                break;
            case TerminalToken.Control control:
                ApplyControl(control.Byte);
                break;
            case TerminalToken.Csi csi:
                ApplyCsi(csi.Sequence);
                break;
            case TerminalToken.Escape escape:
                switch (escape.Final)
                {
                    case (byte)'7': _savedCursor = (Row, Column); break;
                    case (byte)'8':
                        if (_savedCursor is { } saved) MoveTo(saved.Row, saved.Column);
                        break;
                    case (byte)'M': MoveTo(Row - 1, Column); break;
                    case (byte)'D': LineFeed(); break;
                    case (byte)'E': LineFeed(); Column = 0; break;
                    case (byte)'c': Reset(); break;
                }
                break;
        }
    }

    public void Apply(IEnumerable<TerminalToken> tokens)
    {
        foreach (var token in tokens) Apply(token);
    }

    public void ReplaceLines(IEnumerable<IReadOnlyList<Cell>> newLines)
    {
        _lines = newLines.Select(line => line.ToList()).ToList();
        if (_lines.Count == 0) _lines.Add([]);
        Row = _lines.Count - 1;
        Column = 0;
    }

    // Writing

    private void Write(string character)
    {
        var isOverstrike = _pendingOverstrike;
        _pendingOverstrike = false;
        EnsureColumn(Column);
        var line = _lines[Row];
        var cell = new Cell(character, Style);
        if (Column < line.Count)
        {
            if (isOverstrike)
            {
                var existing = line[Column];
                // man(1) style formatting: "x\bx" is bold, "_\bx" is underlined.
                if (existing.Character == character)
                {
                    cell = cell with { Style = cell.Style with { Flags = cell.Style.Flags | StyleFlags.Bold } };
                }
                else if (existing.Character == "_")
                {
                    cell = cell with { Style = cell.Style with { Flags = cell.Style.Flags | StyleFlags.Underline } };
                }
                else if (character == "_")
                {
                    cell = existing with { Style = existing.Style with { Flags = existing.Style.Flags | StyleFlags.Underline } };
                }
            }
            line[Column] = cell;
        }
        else
        {
            line.Add(cell);
        }
        Column++;
    }

    private void ApplyControl(byte b)
    {
        switch (b)
        {
            case 0x0A or 0x0B or 0x0C: // LF, VT, FF
                LineFeed();
                Column = 0;
                break;
            case 0x0D: // CR
                Column = 0;
                break;
            case 0x08: // BS
                if (Column > 0)
                {
                    Column--;
                    _pendingOverstrike = true;
                }
                break;
            case 0x09: // TAB
                var next = (Column / 8 + 1) * 8;
                EnsureColumn(next);
                Column = next;
                break;
        }
    }

    private void LineFeed()
    {
        Row++;
        if (Row >= _lines.Count)
        {
            _lines.Add([]);
            TrimIfNeeded();
        }
    }

    private void TrimIfNeeded()
    {
        var overflow = _lines.Count - MaxLines;
        if (overflow <= 0) return;
        _lines.RemoveRange(0, overflow);
        Row = Math.Max(0, Row - overflow);
        DroppedLines += overflow;
        _savedCursor = null;
    }

    /// <summary>Pads the current line with blanks so <paramref name="column"/> is addressable.</summary>
    private void EnsureColumn(int column)
    {
        var line = _lines[Row];
        var missing = column - line.Count;
        if (missing > 0)
        {
            var blank = new Cell(" ", Style.BackgroundOnly);
            for (var i = 0; i < missing; i++) line.Add(blank);
        }
    }

    private int ScreenTop => Math.Max(0, _lines.Count - ScreenRows);

    private void MoveTo(int row, int column)
    {
        // The cursor can't leave the virtual screen upwards.
        Row = Math.Max(row, ScreenTop);
        while (Row >= _lines.Count)
        {
            _lines.Add([]);
        }
        TrimIfNeeded();
        Column = Math.Max(0, column);
    }

    private void Reset()
    {
        _lines = [[]];
        Row = 0;
        Column = 0;
        Style = TextStyle.Plain;
        _savedCursor = null;
    }

    // CSI

    private void ApplyCsi(CsiSequence csi)
    {
        if (csi.Intermediates.Count > 0) return;
        if (csi.Marker is not null) return; // private modes (e.g. ?25l) don't affect text

        var n = Math.Max(1, csi.Param(0, 1));
        var line = _lines[Row];
        switch ((char)csi.Final)
        {
            case 'm':
                ApplySgr(csi.Params);
                break;
            case 'K':
                EraseInLine(csi.Param(0, 0));
                break;
            case 'J':
                EraseInDisplay(csi.Param(0, 0));
                break;
            case 'A':
                MoveTo(Row - n, Column);
                break;
            case 'B':
                MoveTo(Row + n, Column);
                break;
            case 'C':
                Column += n;
                break;
            case 'D':
                Column = Math.Max(0, Column - n);
                break;
            case 'E':
                MoveTo(Row + n, 0);
                break;
            case 'F':
                MoveTo(Row - n, 0);
                break;
            case 'G' or '`':
                Column = Math.Max(0, csi.Param(0, 1) - 1);
                break;
            case 'H' or 'f':
                MoveTo(ScreenTop + Math.Max(1, csi.Param(0, 1)) - 1, Math.Max(1, csi.Param(1, 1)) - 1);
                break;
            case 'd':
                MoveTo(ScreenTop + Math.Max(1, csi.Param(0, 1)) - 1, Column);
                break;
            case 'X':
                EnsureColumn(Column);
                var blank = new Cell(" ", Style.BackgroundOnly);
                for (var i = Column; i < Math.Min(line.Count, Column + n); i++) line[i] = blank;
                break;
            case 'P':
                if (Column < line.Count)
                {
                    line.RemoveRange(Column, Math.Min(line.Count, Column + n) - Column);
                }
                break;
            case '@':
                EnsureColumn(Column);
                line.InsertRange(Column, Enumerable.Repeat(Cell.Blank, n));
                break;
            case 's':
                _savedCursor = (Row, Column);
                break;
            case 'u':
                if (_savedCursor is { } saved) MoveTo(saved.Row, saved.Column);
                break;
        }
    }

    private void EraseInLine(int mode)
    {
        var line = _lines[Row];
        switch (mode)
        {
            case 0:
                if (Column < line.Count) line.RemoveRange(Column, line.Count - Column);
                break;
            case 1:
                EnsureColumn(Column);
                var end = Math.Min(Column, line.Count - 1);
                for (var i = 0; i <= end; i++) line[i] = Cell.Blank;
                break;
            case 2:
                line.Clear();
                break;
        }
    }

    private void EraseInDisplay(int mode)
    {
        switch (mode)
        {
            case 0:
                EraseInLine(0);
                if (Row + 1 < _lines.Count) _lines.RemoveRange(Row + 1, _lines.Count - Row - 1);
                break;
            case 1:
                for (var i = ScreenTop; i < Row; i++) _lines[i] = [];
                EraseInLine(1);
                break;
            case 2 or 3:
                // `clear` inside a command's output: start the visible output over.
                Reset();
                break;
        }
    }

    private void ApplySgr(IReadOnlyList<int?> parameters)
    {
        if (parameters.Count == 0)
        {
            Style = TextStyle.Plain;
            return;
        }
        var index = 0;
        int? Next()
        {
            index++;
            return index < parameters.Count ? parameters[index] : null;
        }
        while (index < parameters.Count)
        {
            var code = parameters[index] ?? 0;
            var style = Style;
            switch (code)
            {
                case 0: style = TextStyle.Plain; break;
                case 1: style = style with { Flags = style.Flags | StyleFlags.Bold }; break;
                case 2: style = style with { Flags = style.Flags | StyleFlags.Dim }; break;
                case 3: style = style with { Flags = style.Flags | StyleFlags.Italic }; break;
                case 4: style = style with { Flags = style.Flags | StyleFlags.Underline }; break;
                case 7: style = style with { Flags = style.Flags | StyleFlags.Inverse }; break;
                case 9: style = style with { Flags = style.Flags | StyleFlags.Strikethrough }; break;
                case 21 or 22: style = style with { Flags = style.Flags & ~(StyleFlags.Bold | StyleFlags.Dim) }; break;
                case 23: style = style with { Flags = style.Flags & ~StyleFlags.Italic }; break;
                case 24: style = style with { Flags = style.Flags & ~StyleFlags.Underline }; break;
                case 27: style = style with { Flags = style.Flags & ~StyleFlags.Inverse }; break;
                case 29: style = style with { Flags = style.Flags & ~StyleFlags.Strikethrough }; break;
                case >= 30 and <= 37: style = style with { Foreground = TermColor.Ansi((byte)(code - 30)) }; break;
                case 39: style = style with { Foreground = null }; break;
                case >= 40 and <= 47: style = style with { Background = TermColor.Ansi((byte)(code - 40)) }; break;
                case 49: style = style with { Background = null }; break;
                case >= 90 and <= 97: style = style with { Foreground = TermColor.Ansi((byte)(code - 90 + 8)) }; break;
                case >= 100 and <= 107: style = style with { Background = TermColor.Ansi((byte)(code - 100 + 8)) }; break;
                case 38 or 48:
                    TermColor? color = null;
                    switch (Next())
                    {
                        case 5:
                            if (Next() is int value) color = Color256(value);
                            break;
                        case 2:
                            var r = Next() ?? 0;
                            var g = Next() ?? 0;
                            var b = Next() ?? 0;
                            color = TermColor.Rgb(Clamp(r), Clamp(g), Clamp(b));
                            break;
                    }
                    style = code == 38 ? style with { Foreground = color } : style with { Background = color };
                    break;
            }
            Style = style;
            index++;
        }
    }

    private static byte Clamp(int value) => (byte)Math.Clamp(value, 0, 255);

    private static TermColor Color256(int value)
    {
        var clamped = Clamp(value);
        return clamped < 16 ? TermColor.Ansi(clamped) : TermColor.Palette(clamped);
    }
}
