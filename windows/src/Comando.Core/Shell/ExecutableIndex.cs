namespace Comando.Core.Shell;

/// <summary>
/// The programs the shell can run, from its PATH: what tells a command
/// (“git status”) from a request in plain words, and what “did you mean” suggests.
/// </summary>
public static class ExecutableIndex
{
    private static readonly string[] Extensions = [".exe", ".cmd", ".bat", ".ps1", ".com"];
    private static readonly object Lock = new();
    private static string _cachedPath = "\0";
    private static HashSet<string> _cached = [];

    /// <summary>Program names without extension, lowercased, for <paramref name="pathEntries"/>.</summary>
    public static IReadOnlySet<string> Names(IReadOnlyList<string> pathEntries)
    {
        var key = string.Join(';', pathEntries);
        lock (Lock)
        {
            if (key == _cachedPath) return _cached;
        }
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in pathEntries)
        {
            try
            {
                var folder = entry.Trim('"');
                if (!System.IO.Directory.Exists(folder)) continue;
                foreach (var file in System.IO.Directory.EnumerateFiles(folder))
                {
                    var extension = Path.GetExtension(file);
                    if (Extensions.Any(e => e.Equals(extension, StringComparison.OrdinalIgnoreCase)))
                    {
                        names.Add(Path.GetFileNameWithoutExtension(file));
                    }
                }
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
            {
            }
        }
        lock (Lock)
        {
            _cachedPath = key;
            _cached = names;
        }
        return names;
    }
}
