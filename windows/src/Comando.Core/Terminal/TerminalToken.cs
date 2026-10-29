namespace Comando.Core.Terminal;

public abstract record TerminalToken
{
    private TerminalToken() { }

    /// <summary>Printable text, already decoded from UTF-8.</summary>
    public sealed record Text(string Value) : TerminalToken;

    /// <summary>A C0 control byte such as <c>\n</c>, <c>\r</c>, <c>\b</c> or <c>\t</c>.</summary>
    public sealed record Control(byte Byte) : TerminalToken;

    public sealed record Csi(CsiSequence Sequence) : TerminalToken;

    /// <summary>Operating System Command payload, without the <c>ESC ]</c> prefix or terminator.</summary>
    public sealed record Osc(string Payload) : TerminalToken;

    /// <summary>A two-byte escape such as <c>ESC 7</c> (save cursor). Intermediates are dropped.</summary>
    public sealed record Escape(byte Final) : TerminalToken;
}

/// <summary>A token together with the exact bytes it was decoded from.</summary>
public readonly record struct ParsedToken(TerminalToken Token, byte[] Raw);

/// <summary>A CSI (Control Sequence Introducer) escape sequence, e.g. <c>ESC [ 1 ; 31 m</c>.</summary>
public sealed class CsiSequence : IEquatable<CsiSequence>
{
    public CsiSequence(byte? marker, IReadOnlyList<int?> parameters, IReadOnlyList<byte> intermediates, byte final)
    {
        Marker = marker;
        Params = parameters;
        Intermediates = intermediates;
        Final = final;
    }

    /// <summary>Private marker such as <c>?</c>, <c>&gt;</c>, <c>&lt;</c> or <c>=</c> (e.g. <c>ESC [ ? 1049 h</c>).</summary>
    public byte? Marker { get; }

    /// <summary>Numeric parameters. Missing parameters are null.</summary>
    public IReadOnlyList<int?> Params { get; }

    public IReadOnlyList<byte> Intermediates { get; }

    public byte Final { get; }

    public int Param(int index, int fallback) =>
        index < Params.Count && Params[index] is int value ? value : fallback;

    public bool Equals(CsiSequence? other) =>
        other is not null
        && Marker == other.Marker
        && Final == other.Final
        && Params.SequenceEqual(other.Params)
        && Intermediates.SequenceEqual(other.Intermediates);

    public override bool Equals(object? obj) => Equals(obj as CsiSequence);

    public override int GetHashCode() => HashCode.Combine(Marker, Final, Params.Count);
}
