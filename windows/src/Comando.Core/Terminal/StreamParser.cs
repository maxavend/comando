using System.Text;

namespace Comando.Core.Terminal;

/// <summary>
/// Incremental tokenizer for the byte stream coming out of the pseudoconsole.
/// </summary>
/// <remarks>
/// It is resilient to escape sequences and UTF-8 code points split across
/// chunk boundaries, which is the normal case when reading from a pipe.
/// </remarks>
public sealed class StreamParser
{
    private enum State
    {
        Ground,
        Escape,
        EscapeIntermediate,
        Csi,
        Osc,
        OscEscape,
        String,        // DCS / SOS / PM / APC: skipped until ST
        StringEscape,
    }

    private const byte Esc = 0x1B;
    private const byte Bel = 0x07;
    private const int MaxSequenceLength = 64 * 1024;

    private State _state = State.Ground;
    private readonly List<byte> _text = [];
    private List<byte> _sequence = [];
    private readonly List<byte> _payload = [];

    public List<ParsedToken> Feed(ReadOnlySpan<byte> bytes)
    {
        var tokens = new List<ParsedToken>();
        foreach (var b in bytes)
        {
            Consume(b, tokens);
        }
        FlushText(tokens, final: false);
        return tokens;
    }

    private void Consume(byte b, List<ParsedToken> tokens)
    {
        switch (_state)
        {
            case State.Ground:
                if (b == Esc)
                {
                    FlushText(tokens, final: true);
                    _sequence = [b];
                    _state = State.Escape;
                }
                else if (b < 0x20 || b == 0x7F)
                {
                    FlushText(tokens, final: true);
                    tokens.Add(new ParsedToken(new TerminalToken.Control(b), [b]));
                }
                else
                {
                    _text.Add(b);
                }
                break;

            case State.Escape:
                _sequence.Add(b);
                switch (b)
                {
                    case (byte)'[':
                        _state = State.Csi;
                        break;
                    case (byte)']':
                        _payload.Clear();
                        _state = State.Osc;
                        break;
                    case (byte)'P' or (byte)'X' or (byte)'^' or (byte)'_':
                        _state = State.String;
                        break;
                    case >= 0x20 and <= 0x2F:
                        _state = State.EscapeIntermediate;
                        break;
                    case Esc:
                        // ESC ESC: restart the sequence.
                        _sequence = [b];
                        break;
                    default:
                        Emit(new TerminalToken.Escape(b), tokens);
                        break;
                }
                break;

            case State.EscapeIntermediate:
                _sequence.Add(b);
                if (b is >= 0x30 and <= 0x7E)
                {
                    Emit(new TerminalToken.Escape(b), tokens);
                }
                else if (b is not (>= 0x20 and <= 0x2F))
                {
                    _state = State.Ground;
                    _sequence = [];
                }
                break;

            case State.Csi:
                _sequence.Add(b);
                if (b is >= 0x40 and <= 0x7E)
                {
                    Emit(new TerminalToken.Csi(ParseCsi(_sequence)), tokens);
                }
                else if (b < 0x20)
                {
                    // C0 controls inside a CSI are executed immediately.
                    _sequence.RemoveAt(_sequence.Count - 1);
                    tokens.Add(new ParsedToken(new TerminalToken.Control(b), [b]));
                }
                else if (_sequence.Count > MaxSequenceLength)
                {
                    _state = State.Ground;
                    _sequence = [];
                }
                break;

            case State.Osc:
                _sequence.Add(b);
                if (b == Bel)
                {
                    EmitOsc(tokens);
                }
                else if (b == Esc)
                {
                    _state = State.OscEscape;
                }
                else if (_payload.Count < MaxSequenceLength)
                {
                    _payload.Add(b);
                }
                break;

            case State.OscEscape:
                _sequence.Add(b);
                if (b == (byte)'\\')
                {
                    EmitOsc(tokens);
                }
                else
                {
                    _payload.Add(Esc);
                    _payload.Add(b);
                    _state = State.Osc;
                }
                break;

            case State.String:
                _sequence.Add(b);
                if (b == Esc)
                {
                    _state = State.StringEscape;
                }
                else if (b == Bel)
                {
                    EmitSkipped(tokens);
                }
                break;

            case State.StringEscape:
                _sequence.Add(b);
                if (b == (byte)'\\')
                {
                    EmitSkipped(tokens);
                }
                else
                {
                    _state = State.String;
                }
                break;
        }
    }

    private void Emit(TerminalToken token, List<ParsedToken> tokens)
    {
        tokens.Add(new ParsedToken(token, [.. _sequence]));
        _sequence = [];
        _state = State.Ground;
    }

    private void EmitOsc(List<ParsedToken> tokens)
    {
        var text = Encoding.UTF8.GetString(_payload.ToArray());
        _payload.Clear();
        Emit(new TerminalToken.Osc(text), tokens);
    }

    /// <summary>
    /// DCS/APC/etc. are not rendered in the chat, but their bytes are kept so
    /// the embedded terminal still receives them.
    /// </summary>
    private void EmitSkipped(List<ParsedToken> tokens)
    {
        tokens.Add(new ParsedToken(new TerminalToken.Osc(""), [.. _sequence]));
        _sequence = [];
        _state = State.Ground;
    }

    /// <summary>
    /// Emits buffered text. When <paramref name="final"/> is false a trailing
    /// incomplete UTF-8 sequence is kept for the next chunk.
    /// </summary>
    private void FlushText(List<ParsedToken> tokens, bool final)
    {
        if (_text.Count == 0) return;
        var cut = _text.Count;
        if (!final)
        {
            cut = CompleteUtf8Prefix(_text);
            if (cut == 0) return;
        }
        var chunk = _text.GetRange(0, cut).ToArray();
        _text.RemoveRange(0, cut);
        tokens.Add(new ParsedToken(new TerminalToken.Text(Encoding.UTF8.GetString(chunk)), chunk));
    }

    /// <summary>Length of the longest prefix that does not end in the middle of a UTF-8 code point.</summary>
    internal static int CompleteUtf8Prefix(IReadOnlyList<byte> bytes)
    {
        var count = bytes.Count;
        var index = count - 1;
        var continuation = 0;
        while (index >= 0 && continuation < 3 && (bytes[index] & 0xC0) == 0x80)
        {
            continuation++;
            index--;
        }
        if (index < 0) return count;
        var expected = bytes[index] switch
        {
            >= 0xC0 and <= 0xDF => 1,
            >= 0xE0 and <= 0xEF => 2,
            >= 0xF0 and <= 0xF7 => 3,
            _ => -1,
        };
        if (expected < 0) return count;
        return continuation < expected ? index : count;
    }

    internal static CsiSequence ParseCsi(IReadOnlyList<byte> bytes)
    {
        // bytes = ESC [ <marker?> <params> <intermediates> <final>
        var final = bytes.Count > 2 ? bytes[^1] : (byte)0;
        var start = 2;
        var end = bytes.Count - 1;
        byte? marker = null;
        if (start < end && bytes[start] is >= 0x3C and <= 0x3F)
        {
            marker = bytes[start];
            start++;
        }
        var parameters = new List<int?>();
        var intermediates = new List<byte>();
        int? current = null;
        var sawParam = false;
        for (var i = start; i < end; i++)
        {
            var b = bytes[i];
            switch (b)
            {
                case >= (byte)'0' and <= (byte)'9':
                    current = unchecked((current ?? 0) * 10 + (b - '0'));
                    sawParam = true;
                    break;
                case (byte)';' or (byte)':':
                    parameters.Add(current);
                    current = null;
                    sawParam = true;
                    break;
                case >= 0x20 and <= 0x2F:
                    intermediates.Add(b);
                    break;
            }
        }
        if (sawParam) parameters.Add(current);
        return new CsiSequence(marker, parameters, intermediates, final);
    }
}
