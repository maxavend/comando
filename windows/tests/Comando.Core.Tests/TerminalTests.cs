using System.Text;
using Comando.Core.Shell;
using Comando.Core.Terminal;

namespace Comando.Core.Tests;

public class StreamParserTests
{
    private static List<TerminalToken> Tokens(params string[] chunks)
    {
        var parser = new StreamParser();
        return chunks.SelectMany(chunk => parser.Feed(Encoding.UTF8.GetBytes(chunk)).Select(t => t.Token)).ToList();
    }

    [Fact]
    public void PlainTextAndControls()
    {
        Assert.Equal(
            new TerminalToken[] { new TerminalToken.Text("hi"), new TerminalToken.Control(0x0D), new TerminalToken.Control(0x0A) },
            Tokens("hi\r\n"));
    }

    [Fact]
    public void CsiWithParameters()
    {
        Assert.Equal(
            new TerminalToken[] { new TerminalToken.Csi(new CsiSequence(null, new int?[] { 1, 31 }, [], (byte)'m')), new TerminalToken.Text("red") },
            Tokens("\u001B[1;31mred"));
    }

    [Fact]
    public void PrivateModeMarker()
    {
        var csi = Assert.IsType<TerminalToken.Csi>(Tokens("\u001B[?1049h")[0]);
        Assert.Equal((byte)'?', csi.Sequence.Marker);
        Assert.True(ShellSession.EntersAlternateScreen(csi.Sequence));
    }

    [Fact]
    public void OscTerminatedByBellAndSt()
    {
        Assert.Equal(new TerminalToken[] { new TerminalToken.Osc("133;D;0") }, Tokens("\u001B]133;D;0\u0007"));
        Assert.Equal(new TerminalToken[] { new TerminalToken.Osc("6973;cwd;C:\\Users") }, Tokens("\u001B]6973;cwd;C:\\Users\u001B\\"));
    }

    [Fact]
    public void SequenceSplitAcrossChunks()
    {
        Assert.Equal(
            new TerminalToken[] { new TerminalToken.Text("ab"), new TerminalToken.Osc("133;C"), new TerminalToken.Text("c"), new TerminalToken.Text("d") },
            Tokens("ab\u001B]13", "3;C\u0007c", "d"));
    }

    [Fact]
    public void Utf8SplitAcrossChunks()
    {
        var parser = new StreamParser();
        var text = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes("añ😀"))
        {
            foreach (var token in parser.Feed([b]))
            {
                if (token.Token is TerminalToken.Text t) text.Append(t.Value);
            }
        }
        Assert.Equal("añ😀", text.ToString());
    }

    [Fact]
    public void RawBytesArePreserved()
    {
        var parser = new StreamParser();
        var input = Encoding.UTF8.GetBytes("x\u001B[0mY\u001B]0;title\u0007");
        Assert.Equal(input, parser.Feed(input).SelectMany(t => t.Raw).ToArray());
    }
}

public class LineBufferTests
{
    private static string Render(string text) => OutputRenderer.PlainText(Encoding.UTF8.GetBytes(text));

    private static LineBuffer Buffer(string text) => OutputRenderer.Buffer(Encoding.UTF8.GetBytes(text));

    [Fact]
    public void LinesAndTrimming() => Assert.Equal("one\ntwo", Render("one\r\ntwo\r\n\r\n"));

    [Fact]
    public void CarriageReturnOverwritesProgress() => Assert.Equal("100%\ndone", Render("10%\r50%\r100%\r\ndone\r\n"));

    [Fact]
    public void EraseLineAfterCarriageReturn() => Assert.Equal("ok", Render("downloading 12345\r\u001B[Kok\r\n"));

    [Fact]
    public void CursorUpRewritesPreviousLine() => Assert.Equal("A\nb", Render("a\r\nb\r\n\u001B[2A\u001B[2KA\r\n"));

    [Fact]
    public void TabsExpandToEightColumns() => Assert.Equal("a       b", Render("a\tb"));

    [Fact]
    public void SgrColorsAndReset()
    {
        var lines = OutputRenderer.TrimmedLines(Buffer("\u001B[1;32mok\u001B[0m!"));
        var runs = OutputRenderer.Runs(lines[0]);
        Assert.Equal(2, runs.Count);
        Assert.Equal("ok", runs[0].Text);
        Assert.Equal(TermColor.Ansi(2), runs[0].Style.Foreground);
        Assert.True(runs[0].Style.Has(StyleFlags.Bold));
        Assert.Equal(TextStyle.Plain, runs[1].Style);
    }

    [Fact]
    public void ExtendedColors()
    {
        var lines = OutputRenderer.TrimmedLines(Buffer("\u001B[38;5;208mA\u001B[38;2;1;2;3mB"));
        var runs = OutputRenderer.Runs(lines[0]);
        Assert.Equal(TermColor.Palette(208), runs[0].Style.Foreground);
        Assert.Equal(TermColor.Rgb(1, 2, 3), runs[1].Style.Foreground);
    }

    [Fact]
    public void ManPageOverstrike()
    {
        var cells = OutputRenderer.TrimmedLines(Buffer("N\bNA\bA _\bx"))[0];
        Assert.Equal("NA x", string.Concat(cells.Select(c => c.Character)));
        Assert.True(cells[0].Style.Has(StyleFlags.Bold));
        Assert.True(cells[3].Style.Has(StyleFlags.Underline));
    }

    [Fact]
    public void ClearScreenStartsOver() => Assert.Equal("new", Render("old\r\n\u001B[H\u001B[2Jnew"));

    [Fact]
    public void LineLimitDropsOldest()
    {
        var buffer = new LineBuffer { MaxLines = 3 };
        for (var i = 0; i < 5; i++)
        {
            buffer.Apply(new TerminalToken.Text(i.ToString()));
            buffer.Apply(new TerminalToken.Control(0x0A));
        }
        Assert.Equal(3, buffer.DroppedLines);
        Assert.Equal(new[] { "3", "4", "" }, buffer.Lines.Select(line => string.Concat(line.Select(c => c.Character))));
    }

    [Fact]
    public void EmojiWithModifierIsOneCell()
    {
        var cells = OutputRenderer.TrimmedLines(Buffer("👍🏽!"))[0];
        Assert.Equal(2, cells.Count);
    }

    [Fact]
    public void TabularOutputIsDetected()
    {
        Assert.True(OutputRenderer.Render(Encoding.UTF8.GetBytes("Name   Size\r\na.txt  12")).IsTabular);
        Assert.False(OutputRenderer.Render(Encoding.UTF8.GetBytes("Hola, mundo")).IsTabular);
    }
}
