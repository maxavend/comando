using System.Text.RegularExpressions;

namespace Comando.Core.Language;

/// <summary>A clickable piece of output: a web address or a file.</summary>
/// <param name="Start">Character offset in the line.</param>
/// <param name="Length">Number of characters.</param>
/// <param name="Target">The URL, or the full path of the file or folder.</param>
/// <param name="IsUrl">True for web addresses, false for files and folders.</param>
public sealed record OutputLink(int Start, int Length, string Target, bool IsUrl);

/// <summary>Finds web addresses and file names in command output, so they can be opened.</summary>
public static partial class OutputLinker
{
    /// <summary>Web addresses in a line of output.</summary>
    public static List<OutputLink> Urls(string line)
    {
        var links = new List<OutputLink>();
        if (!line.Contains("://")) return links;
        foreach (Match match in UrlPattern().Matches(line))
        {
            var value = match.Value.TrimEnd('.', ',', ')', ']', '\'', '"', ';', ':');
            if (Uri.TryCreate(value, UriKind.Absolute, out _)) links.Add(new OutputLink(match.Index, value.Length, value, true));
        }
        return links;
    }

    /// <summary>The first address of a server running on this PC (dev servers print one).</summary>
    public static Uri? FirstLocalUrl(string text)
    {
        foreach (var link in Urls(text))
        {
            if (!Uri.TryCreate(link.Target, UriKind.Absolute, out var url)) continue;
            if (url.Host is "localhost" or "127.0.0.1" or "0.0.0.0" or "[::1]" or "::1")
            {
                // 0.0.0.0 means “every address”; the browser needs a real one.
                return url.Host == "0.0.0.0" ? new UriBuilder(url) { Host = "localhost" }.Uri : url;
            }
        }
        return null;
    }

    /// <summary>Absolute Windows paths (<c>C:\Users\ana\notas.txt</c>) in a line, when <paramref name="exists"/> says they're real.</summary>
    public static List<OutputLink> AbsolutePaths(string line, Func<string, bool>? exists = null)
    {
        var links = new List<OutputLink>();
        exists ??= path => File.Exists(path) || Directory.Exists(path);
        foreach (Match match in WindowsPathPattern().Matches(line))
        {
            var value = match.Value.TrimEnd('.', ',', ')', ']', ':', ';');
            if (exists(value)) links.Add(new OutputLink(match.Index, value.Length, value, false));
        }
        return links;
    }

    /// <summary>The folder whose contents <paramref name="command"/> lists, or null if it isn't a listing.</summary>
    public static string? ListedFolder(string command, string directory)
    {
        var words = ShellWords.Split(command);
        if (words.Count == 0 || CommandGlossary.Canonical(words[0]) != "get-childitem") return null;
        var targets = new List<string>();
        for (var i = 1; i < words.Count; i++)
        {
            var word = words[i];
            if (word.Equals("-Path", StringComparison.OrdinalIgnoreCase) || word.Equals("-LiteralPath", StringComparison.OrdinalIgnoreCase)) continue;
            if (word.StartsWith('-'))
            {
                // Options that change what's listed (-Recurse, -Filter) make names relative to other folders.
                if (word.StartsWith("-r", StringComparison.OrdinalIgnoreCase) || word.StartsWith("-fi", StringComparison.OrdinalIgnoreCase)
                    || word.StartsWith("-i", StringComparison.OrdinalIgnoreCase) || word.StartsWith("-e", StringComparison.OrdinalIgnoreCase)) return null;
                continue;
            }
            targets.Add(word);
        }
        if (targets.Count > 1) return null;
        if (targets.Count == 0) return directory;
        var target = targets[0];
        if (target.StartsWith('~')) target = Path.Combine(FolderName.Home, target.TrimStart('~', '\\', '/'));
        var path = Path.IsPathRooted(target) ? target : Path.Combine(directory, target);
        return Directory.Exists(path) ? Path.GetFullPath(path) : null;
    }

    /// <summary>Links to the entries of <paramref name="folder"/> named in a line of a listing.</summary>
    public static List<OutputLink> FolderEntries(string line, string folder)
    {
        HashSet<string> entries;
        try
        {
            entries = Directory.EnumerateFileSystemEntries(folder).Select(path => Path.GetFileName(path))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return [];
        }
        return Names(line, entries).Select(found => found with { Target = Path.Combine(folder, found.Target) }).ToList();
    }

    /// <summary>
    /// Names found in one line of a listing. Names may contain spaces, so
    /// words are joined greedily into the longest run that matches a real entry.
    /// <see cref="OutputLink.Target"/> is the entry's name.
    /// </summary>
    public static List<OutputLink> Names(string line, IReadOnlySet<string> entries)
    {
        var words = new List<(int Start, int End)>();
        var index = 0;
        while (index < line.Length)
        {
            while (index < line.Length && (line[index] == ' ' || line[index] == '\t')) index++;
            var start = index;
            while (index < line.Length && line[index] != ' ' && line[index] != '\t') index++;
            if (index > start) words.Add((start, index));
        }

        var found = new List<OutputLink>();
        var first = 0;
        while (first < words.Count)
        {
            var matched = false;
            for (var last = words.Count - 1; last >= first; last--)
            {
                var candidate = line[words[first].Start..words[last].End];
                if (EntryName(candidate, entries) is { } name)
                {
                    found.Add(new OutputLink(words[first].Start, words[last].End - words[first].Start, name, false));
                    first = last + 1;
                    matched = true;
                    break;
                }
            }
            if (!matched) first++;
        }
        return found;
    }

    /// <summary>The entry <paramref name="candidate"/> refers to, allowing a trailing slash or symlink arrow.</summary>
    private static string? EntryName(string candidate, IReadOnlySet<string> entries)
    {
        var name = candidate;
        var arrow = name.IndexOf(" -> ", StringComparison.Ordinal);
        if (arrow >= 0) name = name[..arrow];
        if (name is "." or "..") return null;
        if (entries.Contains(name)) return name;
        if (name.Length > 1 && name[^1] is '\\' or '/' or '*')
        {
            name = name[..^1];
            if (entries.Contains(name)) return name;
        }
        return null;
    }

    [GeneratedRegex(@"https?://[^\s""'<>`]+", RegexOptions.IgnoreCase)]
    private static partial Regex UrlPattern();

    [GeneratedRegex(@"\b[A-Za-z]:\\[^\s""'<>|*?]*")]
    private static partial Regex WindowsPathPattern();
}

/// <summary>Reads progress (“45%”, “12/80”) from the line a command keeps rewriting.</summary>
public static partial class ProgressParser
{
    /// <param name="Fraction">From 0 to 1.</param>
    /// <param name="Label">The line without bar drawings, e.g. “Descargando paquete… 45%”.</param>
    public sealed record Progress(double Fraction, string Label);

    public static Progress? Parse(string line)
    {
        var text = line.Trim();
        if (text.Length == 0) return null;
        double? fraction = null;
        var percent = PercentPattern().Match(text);
        if (percent.Success && double.TryParse(percent.Groups[1].Value.Replace(',', '.'), System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var value) && value <= 100)
        {
            fraction = value / 100;
        }
        else
        {
            var count = CountPattern().Match(text);
            if (count.Success && double.TryParse(count.Groups[1].Value, out var done) && double.TryParse(count.Groups[2].Value, out var total)
                && total > 0 && done <= total && (text.Contains('[') || text.Contains("progress", StringComparison.OrdinalIgnoreCase)))
            {
                fraction = done / total;
            }
        }
        if (fraction is not { } result) return null;
        // Drop bar drawings like [=====>    ] or ████░░░.
        var label = AsciiBar().Replace(text, "");
        label = BlockBar().Replace(label, "");
        label = Spaces().Replace(label, " ").Trim();
        return new Progress(result, label);
    }

    [GeneratedRegex(@"(\d{1,3}(?:[.,]\d+)?)\s?%")]
    private static partial Regex PercentPattern();

    [GeneratedRegex(@"\b(\d+)\s?/\s?(\d+)\b")]
    private static partial Regex CountPattern();

    [GeneratedRegex(@"\[[=#>\-\s.*]+\]")]
    private static partial Regex AsciiBar();

    [GeneratedRegex("[█▉▊▋▌▍▎▏░▒▓■□━─]+")]
    private static partial Regex BlockBar();

    [GeneratedRegex(@"\s{2,}")]
    private static partial Regex Spaces();
}
