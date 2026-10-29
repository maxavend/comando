namespace Comando.Core.Pty;

public sealed record PtyStartInfo(
    string Executable,
    IReadOnlyList<string> Arguments,
    IReadOnlyDictionary<string, string> Environment,
    string WorkingDirectory,
    int Columns,
    int Rows);

/// <summary>
/// A process running in a pseudo-terminal. Events arrive on a background
/// thread; <see cref="Shell.ShellSession"/> moves them to the UI thread.
/// </summary>
public interface IPseudoTerminal : IDisposable
{
    event Action<byte[]>? DataReceived;
    event Action<int?>? Exited;

    bool IsRunning { get; }

    void Start(PtyStartInfo info);
    void Write(ReadOnlySpan<byte> bytes);
    void Resize(int columns, int rows);
}
