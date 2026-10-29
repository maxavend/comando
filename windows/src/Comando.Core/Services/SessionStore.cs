using System.Text.Json;
using Comando.Core.Models;
using Comando.Core.Shell;

namespace Comando.Core.Services;

/// <summary>
/// Keeps sessions and their history in a JSON file. Saves are coalesced, so
/// a burst of changes writes once.
/// </summary>
public sealed class SessionStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = false };
    private readonly string _path;
    private readonly object _lock = new();
    private CancellationTokenSource? _pending;

    public SessionStore(string? path = null)
    {
        _path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Comando", "sessions.json");
    }

    public List<TerminalSession> Load()
    {
        try
        {
            if (!File.Exists(_path)) return [];
            using var stream = File.OpenRead(_path);
            return JsonSerializer.Deserialize<List<TerminalSession>>(stream, Options) ?? [];
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            // A damaged file shouldn't keep the app from opening; keep a copy.
            TryBackUp();
            return [];
        }
    }

    /// <summary>
    /// Saves shortly after the last change. The sessions are serialized on
    /// the UI thread, where they change, and written on a background thread.
    /// </summary>
    public void ScheduleSave(IReadOnlyList<TerminalSession> sessions, IDispatcher dispatcher)
    {
        _pending?.Cancel();
        var pending = new CancellationTokenSource();
        _pending = pending;
        _ = Task.Delay(500, pending.Token).ContinueWith(task =>
        {
            if (task.IsCanceled) return;
            dispatcher.Post(() =>
            {
                var json = JsonSerializer.SerializeToUtf8Bytes(sessions, Options);
                _ = Task.Run(() => Write(json));
            });
        }, TaskScheduler.Default);
    }

    /// <summary>Saves right away (when the app closes).</summary>
    public void Save(IReadOnlyList<TerminalSession> sessions)
    {
        _pending?.Cancel();
        Write(JsonSerializer.SerializeToUtf8Bytes(sessions, Options));
    }

    private void Write(byte[] json)
    {
        lock (_lock)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
                var temporary = _path + ".tmp";
                File.WriteAllBytes(temporary, json);
                File.Move(temporary, _path, overwrite: true);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                // The next change tries again.
            }
        }
    }

    private void TryBackUp()
    {
        try
        {
            if (File.Exists(_path)) File.Copy(_path, _path + ".damaged", overwrite: true);
        }
        catch (IOException)
        {
        }
    }
}
