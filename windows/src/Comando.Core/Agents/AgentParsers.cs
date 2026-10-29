using System.Text.Json;

namespace Comando.Core.Agents;

/// <summary>What an agent CLI reports, the same for every CLI.</summary>
public abstract record AgentEvent
{
    private AgentEvent() { }

    /// <summary>The conversation's id, to resume it later.</summary>
    public sealed record Conversation(string Id) : AgentEvent;

    public sealed record Text(string Value) : AgentEvent;

    public sealed record ToolStarted(string Id, string Name, IReadOnlyDictionary<string, string> Input) : AgentEvent;

    public sealed record ToolFinished(string Id, string? Output, bool IsFailed) : AgentEvent;

    /// <summary>The turn ended. <paramref name="Denied"/> names actions the agent wasn't allowed to do.</summary>
    public sealed record TurnFinished(IReadOnlyList<string> Denied, string? Error) : AgentEvent;

    public sealed record Failed(string Message) : AgentEvent;
}

/// <summary>Turns the lines a CLI prints into events.</summary>
public interface IAgentOutputParser
{
    IReadOnlyList<AgentEvent> Parse(string line);
}

internal static class AgentJson
{
    private static readonly AgentEvent[] None = [];

    public static IReadOnlyList<AgentEvent> Empty => None;

    /// <summary>The line as a JSON object, or null when it isn't one.</summary>
    public static JsonElement? Object(string line)
    {
        var trimmed = line.Trim();
        if (!trimmed.StartsWith('{')) return null;
        try
        {
            using var document = JsonDocument.Parse(trimmed);
            return document.RootElement.ValueKind == JsonValueKind.Object ? document.RootElement.Clone() : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static JsonElement? Get(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) ? value : null;

    public static string? String(this JsonElement? element) =>
        element is { ValueKind: JsonValueKind.String } value ? value.GetString() : null;

    public static string? String(this JsonElement element, string name) => element.Get(name).String();

    public static bool? Bool(this JsonElement element, string name) => element.Get(name) switch
    {
        { ValueKind: JsonValueKind.True } => true,
        { ValueKind: JsonValueKind.False } => false,
        _ => null,
    };

    public static int? Int(this JsonElement element, string name) =>
        element.Get(name) is { ValueKind: JsonValueKind.Number } number && number.TryGetInt32(out var value) ? value : null;

    public static IEnumerable<JsonElement> Array(this JsonElement element, string name) =>
        element.Get(name) is { ValueKind: JsonValueKind.Array } array ? array.EnumerateArray() : Enumerable.Empty<JsonElement>();

    /// <summary>The value as text, for ids that may be numbers.</summary>
    public static string Raw(this JsonElement? element) => element switch
    {
        { ValueKind: JsonValueKind.String } value => value.GetString() ?? "",
        { ValueKind: JsonValueKind.Number } value => value.GetRawText(),
        _ => "",
    };

    /// <summary>Only the string-valued (and numeric) parameters, which is what the cards show.</summary>
    public static IReadOnlyDictionary<string, string> Strings(this JsonElement? element)
    {
        var result = new Dictionary<string, string>();
        if (element is not { ValueKind: JsonValueKind.Object } value) return result;
        foreach (var property in value.EnumerateObject())
        {
            if (property.Value.ValueKind == JsonValueKind.String) result[property.Name] = property.Value.GetString() ?? "";
            else if (property.Value.ValueKind == JsonValueKind.Number) result[property.Name] = property.Value.GetRawText();
        }
        return result;
    }
}

/// <summary>
/// Antigravity CLI (<c>agy --output-format=stream-json</c>): <c>step_update</c>
/// events with text deltas and tool steps, and a <c>result</c> per turn.
/// </summary>
public sealed class AgyParser : IAgentOutputParser
{
    public IReadOnlyList<AgentEvent> Parse(string line)
    {
        if (AgentJson.Object(line) is not { } json || json.String("event") is not { } kind) return AgentJson.Empty;
        switch (kind)
        {
            case "init":
                return json.String("conversation_id") is { } id ? new AgentEvent[] { new AgentEvent.Conversation(id) } : AgentJson.Empty;
            case "step_update":
                if (json.Get("step_update") is not { } step) return AgentJson.Empty;
                var state = step.String("state") ?? "";
                switch (step.String("step_type"))
                {
                    case "agent_response":
                        return step.String("text_delta") is { } text ? new AgentEvent[] { new AgentEvent.Text(text) } : AgentJson.Empty;
                    case "tool":
                        var stepId = step.Get("step_index").Raw();
                        var info = step.Get("tool_info");
                        var name = step.String("tool_name") ?? info?.String("name") ?? "tool";
                        if (state == "ACTIVE")
                        {
                            return new AgentEvent[] { new AgentEvent.ToolStarted(stepId, name, info?.Get("parameters").Strings() ?? new Dictionary<string, string>()) };
                        }
                        var error = info?.Get("error")?.String("message");
                        return new AgentEvent[] { new AgentEvent.ToolFinished(stepId, info?.String("output") ?? error, state == "ERROR") };
                    default:
                        return AgentJson.Empty;
                }
            case "result":
                if (json.Get("result") is not { } result) return AgentJson.Empty;
                var denied = result.Array("denied_actions").Select(a => a.String("action")).OfType<string>().ToList();
                var failed = result.String("status") == "ERROR";
                return new AgentEvent[] { new AgentEvent.TurnFinished(denied, failed ? result.String("error") ?? "" : null) };
            default:
                return AgentJson.Empty;
        }
    }
}

/// <summary>
/// Claude Code and Qwen Code (<c>--output-format stream-json</c>): text arrives
/// as stream events when partial messages are on, and as whole assistant
/// messages otherwise; tool results come back as user messages.
/// </summary>
public sealed class ClaudeStreamParser : IAgentOutputParser
{
    /// <summary>Whether this turn's text already arrived in pieces.</summary>
    private bool _streamedText;

    public IReadOnlyList<AgentEvent> Parse(string line)
    {
        if (AgentJson.Object(line) is not { } json || json.String("type") is not { } type) return AgentJson.Empty;
        switch (type)
        {
            case "system":
                if (json.String("subtype") != "init") return AgentJson.Empty;
                return json.String("session_id") is { } id ? new AgentEvent[] { new AgentEvent.Conversation(id) } : AgentJson.Empty;
            case "stream_event":
                if (json.Get("event") is not { } streamEvent || streamEvent.String("type") != "content_block_delta"
                    || streamEvent.Get("delta") is not { } delta || delta.String("type") != "text_delta"
                    || delta.String("text") is not { } piece)
                {
                    return AgentJson.Empty;
                }
                _streamedText = true;
                return new AgentEvent[] { new AgentEvent.Text(piece) };
            case "assistant":
            {
                var events = new List<AgentEvent>();
                var blocks = json.Get("message") is { } message ? message.Array("content") : Enumerable.Empty<JsonElement>();
                foreach (var block in blocks)
                {
                    switch (block.String("type"))
                    {
                        case "text" when !_streamedText:
                            if (block.String("text") is { } text) events.Add(new AgentEvent.Text(text));
                            break;
                        case "tool_use":
                            events.Add(new AgentEvent.ToolStarted(block.String("id") ?? "", block.String("name") ?? "tool", block.Get("input").Strings()));
                            break;
                    }
                }
                return events;
            }
            case "user":
            {
                var events = new List<AgentEvent>();
                var blocks = json.Get("message") is { } message ? message.Array("content") : Enumerable.Empty<JsonElement>();
                foreach (var block in blocks)
                {
                    if (block.String("type") != "tool_result") continue;
                    string? output = block.Get("content") switch
                    {
                        { ValueKind: JsonValueKind.String } text => text.GetString(),
                        { ValueKind: JsonValueKind.Array } parts => string.Join("\n", parts.EnumerateArray().Select(p => p.String("text")).OfType<string>()),
                        _ => null,
                    };
                    events.Add(new AgentEvent.ToolFinished(block.String("tool_use_id") ?? "", output, block.Bool("is_error") ?? false));
                }
                return events;
            }
            case "result":
            {
                _streamedText = false;
                var denied = json.Array("permission_denials").Select(d => d.String("tool_name")).OfType<string>().ToList();
                var isError = json.Bool("is_error") ?? false;
                var message = json.String("result") ?? json.String("subtype") ?? "";
                return new AgentEvent[] { new AgentEvent.TurnFinished(denied, isError ? message : null) };
            }
            default:
                return AgentJson.Empty;
        }
    }
}

/// <summary>Codex (<c>codex exec --json</c>): items that start and complete, and a turn that completes or fails.</summary>
public sealed class CodexParser : IAgentOutputParser
{
    public IReadOnlyList<AgentEvent> Parse(string line)
    {
        if (AgentJson.Object(line) is not { } json || json.String("type") is not { } type) return AgentJson.Empty;
        switch (type)
        {
            case "thread.started":
                return json.String("thread_id") is { } id ? new AgentEvent[] { new AgentEvent.Conversation(id) } : AgentJson.Empty;
            case "item.started" or "item.completed":
                if (json.Get("item") is not { } item) return AgentJson.Empty;
                var itemId = item.String("id") ?? "";
                var done = type == "item.completed";
                switch (item.String("type"))
                {
                    case "agent_message":
                        return done && item.String("text") is { } text ? new AgentEvent[] { new AgentEvent.Text(text) } : AgentJson.Empty;
                    case "command_execution":
                        var input = new Dictionary<string, string> { ["command"] = item.String("command") ?? "" };
                        var started = new AgentEvent.ToolStarted(itemId, "command_execution", input);
                        if (!done) return new AgentEvent[] { started };
                        var exit = item.Int("exit_code") ?? 0;
                        return new AgentEvent[] { started, new AgentEvent.ToolFinished(itemId, item.String("aggregated_output"), exit != 0) };
                    case "file_change":
                        if (!done) return AgentJson.Empty;
                        var paths = item.Array("changes").Select(c => c.String("path")).OfType<string>();
                        return new AgentEvent[]
                        {
                            new AgentEvent.ToolStarted(itemId, "file_change", new Dictionary<string, string> { ["path"] = string.Join(", ", paths) }),
                            new AgentEvent.ToolFinished(itemId, null, item.String("status") == "failed"),
                        };
                    default:
                        return AgentJson.Empty;
                }
            case "turn.completed":
                return new AgentEvent[] { new AgentEvent.TurnFinished(System.Array.Empty<string>(), null) };
            case "turn.failed":
                var message = json.Get("error")?.String("message") ?? "";
                return new AgentEvent[] { new AgentEvent.TurnFinished(System.Array.Empty<string>(), Readable(message)) };
            default:
                return AgentJson.Empty;
        }
    }

    /// <summary>Codex wraps API errors in JSON inside the message.</summary>
    public static string Readable(string message)
    {
        if (AgentJson.Object(message) is { } inner && inner.Get("error") is { } error && error.String("message") is { } text) return text;
        return message;
    }
}
