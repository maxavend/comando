using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Comando.Core.Agents;

public enum AgentStepKind
{
    Text,
    Tool,
}

public enum AgentStepState
{
    Running,
    Done,
    Failed,
}

/// <summary>One piece of an agent's answer: some text, or a tool it used.</summary>
public sealed class AgentStep
{
    public string Id { get; set; } = "";
    public AgentStepKind Kind { get; set; }

    /// <summary>The text, or what the tool did (“Ejecutó un comando”).</summary>
    public string Text { get; set; } = "";

    /// <summary>What the tool tried, when it didn't work (“No pudo crear saludo.txt”).</summary>
    public string? FailedText { get; set; }

    /// <summary>A Segoe Fluent Icons glyph for the card.</summary>
    public string? Glyph { get; set; }

    /// <summary>The command or file the tool worked on, for the card.</summary>
    public string? Detail { get; set; }

    public string? Output { get; set; }
    public AgentStepState State { get; set; } = AgentStepState.Done;

    public AgentStep Copy() => (AgentStep)MemberwiseClone();
}

/// <summary>
/// An agent's answer to one message, in order: text and the tools it used.
/// Stored with the entry so the conversation survives relaunch.
/// </summary>
public sealed partial class AgentReply
{
    public List<AgentStep> Steps { get; set; } = [];

    /// <summary>Actions the agent wasn't allowed to do this turn.</summary>
    public List<string> Denied { get; set; } = [];

    public string? Error { get; set; }

    /// <summary>The error needs the CLI's own screen; Comando opened it.</summary>
    public bool? OpenedTerminal { get; set; }

    public bool IsFinished { get; set; }

    /// <summary>All the text, for search and the sidebar.</summary>
    [JsonIgnore]
    public string Text => string.Concat(Steps.Where(s => s.Kind == AgentStepKind.Text).Select(s => s.Text));

    /// <summary>A copy, so a view holding the old one isn't changed under it.</summary>
    public AgentReply Copy() => new()
    {
        Steps = Steps.Select(s => s.Copy()).ToList(),
        Denied = [.. Denied],
        Error = Error,
        OpenedTerminal = OpenedTerminal,
        IsFinished = IsFinished,
    };

    public void Apply(AgentEvent agentEvent, AgentKind agent)
    {
        switch (agentEvent)
        {
            case AgentEvent.Conversation:
                break;
            case AgentEvent.Text text:
                if (Steps.Count > 0 && Steps[^1].Kind == AgentStepKind.Text)
                {
                    Steps[^1].Text += text.Value;
                }
                else
                {
                    Steps.Add(new AgentStep { Id = $"text-{Steps.Count}", Kind = AgentStepKind.Text, Text = text.Value });
                }
                break;
            case AgentEvent.ToolStarted started:
                var summary = new ToolSummary(agent, started.Name, started.Input);
                var existing = Steps.FindIndex(s => s.Kind == AgentStepKind.Tool && s.Id == started.Id);
                if (existing >= 0)
                {
                    Steps[existing].Text = summary.Text;
                }
                else
                {
                    TrimLastText();
                    Steps.Add(new AgentStep
                    {
                        Id = started.Id,
                        Kind = AgentStepKind.Tool,
                        Text = summary.Text,
                        FailedText = summary.FailedText,
                        Glyph = summary.Glyph,
                        Detail = summary.Detail,
                        State = AgentStepState.Running,
                    });
                }
                break;
            case AgentEvent.ToolFinished finished:
                var index = Steps.FindLastIndex(s => s.Kind == AgentStepKind.Tool && s.Id == finished.Id);
                if (index < 0) return;
                Steps[index].Output = finished.Output is null ? null : Clean(finished.Output);
                Steps[index].State = finished.IsFailed ? AgentStepState.Failed : AgentStepState.Done;
                break;
            case AgentEvent.TurnFinished turn:
                Denied = turn.Denied.Distinct().OrderBy(d => d, StringComparer.Ordinal).ToList();
                if (!string.IsNullOrEmpty(turn.Error)) Error = turn.Error;
                Finish();
                break;
            case AgentEvent.Failed failed:
                Error = failed.Message;
                Finish();
                break;
        }
    }

    public void Finish()
    {
        IsFinished = true;
        foreach (var step in Steps)
        {
            if (step.State == AgentStepState.Running) step.State = AgentStepState.Done;
        }
        TrimLastText();
    }

    /// <summary>Line breaks at the edges would leave the bubble with empty lines.</summary>
    private void TrimLastText()
    {
        if (Steps.Count == 0 || Steps[^1].Kind != AgentStepKind.Text) return;
        Steps[^1].Text = Steps[^1].Text.Trim();
        if (Steps[^1].Text.Length == 0) Steps.RemoveAt(Steps.Count - 1);
    }

    /// <summary>Terminal output with CRLF line ends and color codes, made readable.</summary>
    public static string Clean(string output)
    {
        var text = AnsiCsi().Replace(output.Replace("\r\n", "\n"), "");
        const int limit = 20_000;
        return text.Length > limit ? text[..limit] + "\n…" : text;
    }

    [GeneratedRegex(@"\x1B\[[0-9;?]*[A-Za-z]")]
    private static partial Regex AnsiCsi();
}

/// <summary>
/// What a tool call did, in Spanish, with a glyph and the thing it touched:
/// “Leyó notas.md”, or “No pudo leer notas.md” when it failed.
/// </summary>
public sealed partial class ToolSummary
{
    public ToolSummary(AgentKind agent, string name, IReadOnlyDictionary<string, string> input)
    {
        string? File(params string[] keys)
        {
            foreach (var key in keys)
            {
                if (input.TryGetValue(key, out var path)) return LastComponent(path);
            }
            return null;
        }
        string? Value(params string[] keys)
        {
            foreach (var key in keys)
            {
                if (input.TryGetValue(key, out var value)) return value;
            }
            return null;
        }

        _ = agent;
        switch (name)
        {
            case "run_command" or "Bash" or "command_execution" or "run_shell_command" or "shell" or "PowerShell":
                (Text, FailedText, Glyph, Detail) = Make("Ejecutó", "ejecutar", "un comando", "", Value("CommandLine", "command", "cmd"));
                break;
            case "view_file" or "Read" or "read_file" or "read_many_files":
                (Text, FailedText, Glyph, Detail) = Make("Leyó", "leer", File("AbsolutePath", "file_path", "path", "TargetFile") ?? "un archivo", "");
                break;
            case "list_dir" or "LS" or "list_directory":
                (Text, FailedText, Glyph, Detail) = Make("Revisó", "revisar", "la carpeta " + (File("DirectoryPath", "path") ?? ""), "");
                break;
            case "write_to_file" or "Write" or "write_file":
                (Text, FailedText, Glyph, Detail) = Make("Creó", "crear", File("TargetFile", "file_path", "path") ?? "un archivo", "");
                break;
            case "replace_file_content" or "multi_replace_file_content" or "sed_file" or "Edit" or "MultiEdit" or "replace" or "edit" or "NotebookEdit" or "notebook_edit":
                (Text, FailedText, Glyph, Detail) = Make("Editó", "editar", File("TargetFile", "file_path", "path", "notebook_path") ?? "un archivo", "");
                break;
            case "file_change":
                (Text, FailedText, Glyph, Detail) = Make("Cambió", "cambiar", Value("path") ?? "archivos", "");
                break;
            case "grep_search" or "Grep" or "search_file_content" or "grep":
                (Text, FailedText, Glyph, Detail) = Make("Buscó", "buscar", $"“{Value("Query", "pattern") ?? ""}”", "");
                break;
            case "find_by_name" or "Glob" or "glob":
                (Text, FailedText, Glyph, Detail) = Make("Buscó", "buscar", "archivos " + (Value("Pattern", "pattern") ?? ""), "");
                break;
            case "search_web" or "WebSearch" or "google_web_search" or "web_search":
                (Text, FailedText, Glyph, Detail) = Make("Buscó", "buscar", $"en la web “{Value("query", "Query") ?? ""}”", "");
                break;
            case "read_url_content" or "WebFetch" or "web_fetch":
                var url = Value("Url", "url");
                var host = url is not null && Uri.TryCreate(url, UriKind.Absolute, out var parsed) ? parsed.Host : "";
                (Text, FailedText, Glyph, Detail) = Make("Leyó", "leer", "una página " + host, "");
                break;
            case "TodoWrite" or "manage_task" or "todo_write":
                (Text, FailedText, Glyph, Detail) = Make("Actualizó", "actualizar", "su lista de tareas", "");
                break;
            case "Task" or "invoke_subagent" or "browser_subagent" or "Agent":
                (Text, FailedText, Glyph, Detail) = Make("Le pidió ayuda", "pedirle ayuda", "a un subagente", "");
                break;
            default:
                var words = CamelCase().Replace(Separators().Replace(name, " "), "$1 $2").ToLowerInvariant();
                (Text, FailedText, Glyph, Detail) = Make("Usó", "usar", words, "");
                break;
        }
    }

    public string Text { get; }
    public string FailedText { get; }
    public string Glyph { get; }
    public string? Detail { get; }

    /// <summary><paramref name="past"/> and <paramref name="infinitive"/> are the same verb: “Leyó”, “leer”.</summary>
    private static (string, string, string, string?) Make(string past, string infinitive, string target, string glyph, string? detail = null)
    {
        var trimmed = target.Trim();
        return ($"{past} {trimmed}".Trim(), $"No pudo {infinitive} {trimmed}".Trim(), glyph, detail);
    }

    private static string LastComponent(string path)
    {
        var trimmed = path.TrimEnd('/', '\\');
        var index = trimmed.LastIndexOfAny(['/', '\\']);
        return index < 0 ? trimmed : trimmed[(index + 1)..];
    }

    [GeneratedRegex("[_-]")]
    private static partial Regex Separators();

    [GeneratedRegex("([a-z])([A-Z])")]
    private static partial Regex CamelCase();
}

/// <summary>Plain-language names for actions an agent wasn't allowed to do.</summary>
public static partial class DeniedAction
{
    public static string Describe(string action) => action switch
    {
        "write_file" or "Write" or "Edit" or "MultiEdit" or "NotebookEdit" or "replace_file_content" or "file_change" => "crear o editar archivos",
        "run_command" or "Bash" or "command" or "PowerShell" => "ejecutar comandos",
        "read_url" or "WebFetch" or "network" or "read_url_content" => "conectarse a internet",
        _ => Separators().Replace(action, " ").ToLowerInvariant(),
    };

    [GeneratedRegex("[_-]")]
    private static partial Regex Separators();
}
