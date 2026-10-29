using System.Text.Json;
using System.Text.RegularExpressions;

namespace Comando.Core.Tools;

/// <summary>A table printed as text: column names and the cells of each row.</summary>
public sealed record TextTable(IReadOnlyList<string> Columns, IReadOnlyList<string[]> Rows);

/// <summary>Reads what each package manager prints. Pure functions, so they're tested with sample output.</summary>
public static partial class PackageParsers
{
    // Text tables (winget, Scoop)

    /// <summary>
    /// Finds the tables in a command's output: a header line followed by a
    /// rule of dashes. Columns come from the dash groups (PowerShell tables,
    /// as Scoop prints them) or, when the rule is one long line (winget),
    /// from where each header word starts.
    /// </summary>
    public static List<TextTable> Tables(string output)
    {
        var lines = CleanLines(output);
        var tables = new List<TextTable>();
        for (var i = 1; i < lines.Count; i++)
        {
            var rule = lines[i].TrimEnd();
            if (!IsRule(rule)) continue;
            var header = lines[i - 1];
            if (string.IsNullOrWhiteSpace(header)) continue;

            var starts = GroupStarts(rule, '-');
            if (starts.Count <= 1) starts = WordStarts(header);
            if (starts.Count == 0) continue;
            var columns = Slice(header, starts);

            var rows = new List<string[]>();
            var j = i + 1;
            for (; j < lines.Count; j++)
            {
                var row = lines[j];
                if (string.IsNullOrWhiteSpace(row)) break;
                // The next table's header.
                if (j + 1 < lines.Count && IsRule(lines[j + 1].TrimEnd())) break;
                // A sentence after the table (“2 upgrades available.”) runs
                // across the column boundary instead of lining up with it.
                if (starts.Count > 1)
                {
                    var boundary = starts[1];
                    if (row.Length <= boundary || row[boundary - 1] != ' ') break;
                }
                rows.Add(Slice(row, starts));
            }
            tables.Add(new TextTable(columns, rows));
            i = j;
        }
        return tables;
    }

    /// <summary>
    /// <c>winget list</c> and <c>winget upgrade</c>. Both print Name, Id,
    /// Version, Available and Source, in the system's language; Available
    /// and Source may be missing. <c>winget upgrade</c> can print a second
    /// table (packages that need to be named explicitly); it's read too.
    /// </summary>
    public static List<InstalledPackage> Winget(string output)
    {
        var packages = new List<InstalledPackage>();
        foreach (var table in Tables(output))
        {
            if (table.Columns.Count < 3) continue;
            var availableIndex = -1;
            var sourceIndex = -1;
            if (table.Columns.Count >= 5)
            {
                availableIndex = 3;
                sourceIndex = 4;
            }
            else if (table.Columns.Count == 4)
            {
                if (AvailableHeaders.Contains(table.Columns[3])) availableIndex = 3;
                else sourceIndex = 3;
            }

            foreach (var row in table.Rows)
            {
                var name = row[0];
                var id = row[1];
                if (id.Length == 0) continue;
                var truncated = id.EndsWith('…');
                var available = availableIndex >= 0 ? row[availableIndex] : "";
                packages.Add(new InstalledPackage(
                    PackageManager.Winget,
                    name.TrimEnd('…').TrimEnd(),
                    truncated ? id.TrimEnd('…') : id,
                    row[2],
                    available.Length > 0 ? available : null)
                {
                    Source = sourceIndex >= 0 ? row[sourceIndex] : null,
                    IsIdTruncated = truncated,
                });
            }
        }
        return packages;
    }

    /// <summary>The “Available” column in the languages winget speaks.</summary>
    private static readonly HashSet<string> AvailableHeaders = new(StringComparer.OrdinalIgnoreCase)
    {
        "Available", "Disponible", "Verfügbar", "Disponibile", "Disponível", "Beschikbaar", "Dostępne", "Доступно", "可用", "利用可能",
    };

    /// <summary><c>scoop list</c>: Name, Version, Source, Updated, Info.</summary>
    public static List<InstalledPackage> ScoopList(string output)
    {
        var packages = new List<InstalledPackage>();
        foreach (var table in Tables(output))
        {
            if (table.Columns.Count < 2) continue;
            foreach (var row in table.Rows)
            {
                if (row[0].Length == 0) continue;
                packages.Add(new InstalledPackage(PackageManager.Scoop, row[0], row[0], row[1])
                {
                    Source = row.Length > 2 && row[2].Length > 0 ? row[2] : null,
                });
            }
        }
        return packages;
    }

    /// <summary><c>scoop status</c>: name → latest version, for what has an update.</summary>
    public static Dictionary<string, string> ScoopStatus(string output)
    {
        var latest = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var table in Tables(output))
        {
            if (table.Columns.Count < 3) continue;
            foreach (var row in table.Rows)
            {
                if (row[0].Length > 0 && row[2].Length > 0) latest[row[0]] = row[2];
            }
        }
        return latest;
    }

    // npm

    /// <summary><c>npm ls -g --depth=0 --json</c>.</summary>
    public static List<InstalledPackage> NpmList(string json, string? nodeVersion = null, string? npmPath = null, bool isActiveNode = true)
    {
        var packages = new List<InstalledPackage>();
        if (Parse(json) is not { } document) return packages;
        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty("dependencies", out var dependencies)
                || dependencies.ValueKind != JsonValueKind.Object)
            {
                return packages;
            }
            foreach (var dependency in dependencies.EnumerateObject())
            {
                var version = Text(dependency.Value, "version") ?? "";
                packages.Add(new InstalledPackage(PackageManager.Npm, dependency.Name, dependency.Name, version)
                {
                    NodeVersion = nodeVersion,
                    NpmPath = npmPath,
                    IsActiveNode = isActiveNode,
                });
            }
        }
        return packages;
    }

    /// <summary><c>npm outdated -g --json</c>: name → latest version. It exits with 1 when something is outdated.</summary>
    public static Dictionary<string, string> NpmOutdated(string json)
    {
        var latest = new Dictionary<string, string>();
        if (Parse(json) is not { } document) return latest;
        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object) return latest;
            foreach (var package in document.RootElement.EnumerateObject())
            {
                if (package.Value.ValueKind != JsonValueKind.Object) continue;
                var current = Text(package.Value, "current");
                var newest = Text(package.Value, "latest");
                if (newest is not null && newest != current) latest[package.Name] = newest;
            }
        }
        return latest;
    }

    // Python tools

    /// <summary><c>pipx list --json</c>.</summary>
    public static List<InstalledPackage> PipxList(string json)
    {
        var packages = new List<InstalledPackage>();
        if (Parse(json) is not { } document) return packages;
        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty("venvs", out var venvs)
                || venvs.ValueKind != JsonValueKind.Object)
            {
                return packages;
            }
            foreach (var venv in venvs.EnumerateObject())
            {
                var name = venv.Name;
                var version = "";
                var commands = new List<string>();
                if (venv.Value.ValueKind == JsonValueKind.Object
                    && venv.Value.TryGetProperty("metadata", out var metadata)
                    && metadata.ValueKind == JsonValueKind.Object
                    && metadata.TryGetProperty("main_package", out var main)
                    && main.ValueKind == JsonValueKind.Object)
                {
                    name = Text(main, "package") ?? name;
                    version = Text(main, "package_version") ?? "";
                    if (main.TryGetProperty("apps", out var apps) && apps.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var app in apps.EnumerateArray())
                        {
                            if (app.ValueKind == JsonValueKind.String) commands.Add(WithoutExe(app.GetString()!));
                        }
                    }
                }
                packages.Add(new InstalledPackage(PackageManager.Pipx, name, name, version) { Commands = commands });
            }
        }
        return packages;
    }

    /// <summary>
    /// <c>uv tool list</c> prints “name v1.2.3” followed by “- command”
    /// lines; with <c>--outdated</c>, “[latest: 1.3.0]” after the version.
    /// </summary>
    public static List<InstalledPackage> UvToolList(string output)
    {
        var packages = new List<InstalledPackage>();
        string? name = null, version = null, latest = null;
        var commands = new List<string>();

        void Flush()
        {
            if (name is not null)
            {
                packages.Add(new InstalledPackage(PackageManager.Uv, name, name, version ?? "", latest) { Commands = commands.ToArray() });
            }
            name = null;
            version = null;
            latest = null;
            commands.Clear();
        }

        foreach (var raw in CleanLines(output))
        {
            var line = raw.Trim();
            if (line.Length == 0) continue;
            if (line.StartsWith("- "))
            {
                if (name is not null) commands.Add(WithoutExe(line[2..].Trim()));
                continue;
            }
            var match = UvToolLine().Match(line);
            if (!match.Success) continue;
            Flush();
            name = match.Groups["name"].Value;
            version = match.Groups["version"].Value;
            latest = match.Groups["latest"].Success ? match.Groups["latest"].Value.Trim() : null;
        }
        Flush();
        return packages;
    }

    // Node versions

    /// <summary>The version <c>node --version</c> prints, without the “v”.</summary>
    public static string? NodeVersion(string output)
    {
        var text = output.Trim();
        if (text.Length == 0) return null;
        return text.StartsWith('v') ? text[1..] : text;
    }

    // Helpers

    /// <summary>Lines as they look on screen: progress spinners drawn with \r and color codes removed.</summary>
    internal static List<string> CleanLines(string output)
    {
        var lines = new List<string>();
        foreach (var raw in output.Replace("\r\n", "\n").Split('\n'))
        {
            var line = raw;
            var lastReturn = line.LastIndexOf('\r');
            if (lastReturn >= 0) line = line[(lastReturn + 1)..];
            lines.Add(AnsiEscape().Replace(line, ""));
        }
        return lines;
    }

    private static bool IsRule(string line) =>
        line.Count(c => c == '-') >= 3 && line.All(c => c is '-' or ' ');

    /// <summary>Where each run of <paramref name="character"/> starts.</summary>
    private static List<int> GroupStarts(string line, char character)
    {
        var starts = new List<int>();
        for (var i = 0; i < line.Length; i++)
        {
            if (line[i] == character && (i == 0 || line[i - 1] != character)) starts.Add(i);
        }
        return starts;
    }

    /// <summary>Where each word of a header starts.</summary>
    private static List<int> WordStarts(string line)
    {
        var starts = new List<int>();
        for (var i = 0; i < line.Length; i++)
        {
            if (line[i] != ' ' && (i == 0 || line[i - 1] == ' ')) starts.Add(i);
        }
        return starts;
    }

    private static string[] Slice(string line, IReadOnlyList<int> starts)
    {
        var cells = new string[starts.Count];
        for (var k = 0; k < starts.Count; k++)
        {
            var start = starts[k];
            var end = k + 1 < starts.Count ? starts[k + 1] : line.Length;
            cells[k] = start >= line.Length ? "" : line[start..Math.Min(end, line.Length)].Trim();
        }
        return cells;
    }

    private static JsonDocument? Parse(string json)
    {
        // npm may print warnings before the JSON.
        var start = json.IndexOf('{');
        if (start < 0) return null;
        try
        {
            return JsonDocument.Parse(json[start..]);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? Text(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static string WithoutExe(string name) =>
        name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name;

    [GeneratedRegex(@"\x1B\[[0-9;?]*[A-Za-z]")]
    private static partial Regex AnsiEscape();

    [GeneratedRegex(@"^(?<name>[^\s\-][^\s]*)\s+v(?<version>[^\s\[\(]+)(?:\s+\[latest:\s*v?(?<latest>[^\]]+)\])?")]
    private static partial Regex UvToolLine();
}
