using Comando.Core.Models;

namespace Comando.Views;

/// <summary>A match in the title bar search: a session, or a command inside one.</summary>
public sealed record SearchResult(TerminalSession Session, CommandEntry? Entry, string Title, string Detail)
{
    public static List<SearchResult> Find(IEnumerable<TerminalSession> sessions, string query, int limit = 8)
    {
        query = query.Trim();
        if (query.Length == 0) return [];
        var results = new List<SearchResult>();
        foreach (var session in sessions)
        {
            if (session.DisplayName.Contains(query, StringComparison.CurrentCultureIgnoreCase))
            {
                results.Add(new SearchResult(session, null, session.DisplayName, "Sesión"));
            }
            // Most recent first: what people look for is usually what they just ran.
            foreach (var entry in session.Entries.Reverse())
            {
                if (results.Count >= limit) return results;
                if (entry.Command.Contains(query, StringComparison.CurrentCultureIgnoreCase))
                {
                    results.Add(new SearchResult(session, entry, entry.Command, session.DisplayName));
                }
                else if (Snippet(entry.PlainOutput, query) is { } snippet)
                {
                    results.Add(new SearchResult(session, entry, snippet, $"{session.DisplayName} · {entry.Command}"));
                }
            }
        }
        return results;
    }

    /// <summary>The line of the output that contains the query.</summary>
    private static string? Snippet(string output, string query)
    {
        var index = output.IndexOf(query, StringComparison.CurrentCultureIgnoreCase);
        if (index < 0) return null;
        var start = output.LastIndexOf('\n', index) + 1;
        var end = output.IndexOf('\n', index);
        var line = output[start..(end < 0 ? output.Length : end)].Trim();
        return line.Length > 120 ? line[..120] + "…" : line;
    }
}
