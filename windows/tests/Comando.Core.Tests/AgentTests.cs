using Comando.Core.Agents;
using Comando.Core.Shell;

namespace Comando.Core.Tests;

public class AgentKindTests
{
    [Fact]
    public void BareNamesStartAgents()
    {
        Assert.Equal(AgentKind.Claude, AgentKinds.FromCommand("claude"));
        Assert.Equal(AgentKind.Codex, AgentKinds.FromCommand("  codex "));
        Assert.Null(AgentKinds.FromCommand("claude --resume abc"));
        Assert.Null(AgentKinds.FromCommand(@".\claude"));
        Assert.Null(AgentKinds.FromCommand("git"));
    }

    [Fact]
    public void ClaudeArgumentsResumeWithPermission()
    {
        var args = AgentKind.Claude.Arguments("abc", AgentPermission.Edits, null);
        Assert.Equal(
            new[] { "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--resume", "abc", "--permission-mode", "acceptEdits" },
            args);
    }

    [Fact]
    public void CodexTakesTheMessageLast()
    {
        var args = AgentKind.Codex.Arguments(null, AgentPermission.Ask, "hola");
        Assert.Equal(new[] { "exec", "--json", "--skip-git-repo-check", "hola" }, args);
    }

    [Fact]
    public void InputLinesAreJson()
    {
        Assert.Equal("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"hola\"}}\n", AgentKind.Claude.InputLine("hola"));
        Assert.Equal("{\"event\":\"user\",\"message\":{\"content\":\"hola\"}}\n", AgentKind.Agy.InputLine("hola"));
    }

    [Fact]
    public void TerminalCommandResumesTheConversation()
    {
        Assert.Equal("claude --resume 'abc'", AgentKind.Claude.TerminalCommand("abc"));
        Assert.Equal("codex resume 'abc'", AgentKind.Codex.TerminalCommand("abc"));
        Assert.Equal("agy", AgentKind.Agy.TerminalCommand(null));
    }
}

public class AgentParserTests
{
    [Fact]
    public void ClaudeStreamsTextAndTools()
    {
        var parser = new ClaudeStreamParser();
        var events = new List<AgentEvent>();
        events.AddRange(parser.Parse("{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\"}"));
        events.AddRange(parser.Parse("{\"type\":\"stream_event\",\"event\":{\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"Hola\"}}}"));
        // The whole message repeats the streamed text; it isn't added twice.
        events.AddRange(parser.Parse("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hola\"},{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Read\",\"input\":{\"file_path\":\"C:\\\\src\\\\notas.md\",\"limit\":20}}]}}"));
        events.AddRange(parser.Parse("{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[{\"type\":\"text\",\"text\":\"línea 1\"}],\"is_error\":false}]}}"));
        events.AddRange(parser.Parse("{\"type\":\"result\",\"is_error\":false,\"result\":\"ok\",\"permission_denials\":[{\"tool_name\":\"Write\"}]}"));

        Assert.Equal(5, events.Count);
        Assert.Equal(new AgentEvent.Conversation("s1"), events[0]);
        Assert.Equal(new AgentEvent.Text("Hola"), events[1]);
        var tool = Assert.IsType<AgentEvent.ToolStarted>(events[2]);
        Assert.Equal("Read", tool.Name);
        Assert.Equal(@"C:\src\notas.md", tool.Input["file_path"]);
        Assert.Equal("20", tool.Input["limit"]);
        var finished = Assert.IsType<AgentEvent.ToolFinished>(events[3]);
        Assert.Equal("línea 1", finished.Output);
        var turn = Assert.IsType<AgentEvent.TurnFinished>(events[4]);
        Assert.Equal(new[] { "Write" }, turn.Denied);
        Assert.Null(turn.Error);
    }

    [Fact]
    public void ClaudeWithoutPartialMessagesUsesWholeText()
    {
        var parser = new ClaudeStreamParser();
        var events = parser.Parse("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Listo\"}]}}");
        Assert.Equal(new AgentEvent.Text("Listo"), Assert.Single(events));
    }

    [Fact]
    public void AgyStepsAndResult()
    {
        var parser = new AgyParser();
        Assert.Equal(new AgentEvent.Conversation("c9"), Assert.Single(parser.Parse("{\"event\":\"init\",\"conversation_id\":\"c9\"}")));
        Assert.Equal(new AgentEvent.Text("Hola"), Assert.Single(parser.Parse("{\"event\":\"step_update\",\"step_update\":{\"step_type\":\"agent_response\",\"text_delta\":\"Hola\"}}")));
        var started = Assert.IsType<AgentEvent.ToolStarted>(Assert.Single(parser.Parse(
            "{\"event\":\"step_update\",\"step_update\":{\"step_type\":\"tool\",\"step_index\":3,\"state\":\"ACTIVE\",\"tool_name\":\"run_command\",\"tool_info\":{\"parameters\":{\"CommandLine\":\"dir\"}}}}")));
        Assert.Equal("3", started.Id);
        Assert.Equal("dir", started.Input["CommandLine"]);
        var finished = Assert.IsType<AgentEvent.ToolFinished>(Assert.Single(parser.Parse(
            "{\"event\":\"step_update\",\"step_update\":{\"step_type\":\"tool\",\"step_index\":3,\"state\":\"ERROR\",\"tool_info\":{\"error\":{\"message\":\"falló\"}}}}")));
        Assert.True(finished.IsFailed);
        Assert.Equal("falló", finished.Output);
        var turn = Assert.IsType<AgentEvent.TurnFinished>(Assert.Single(parser.Parse(
            "{\"event\":\"result\",\"result\":{\"status\":\"ERROR\",\"error\":\"sin cuota\",\"denied_actions\":[{\"action\":\"write_file\"}]}}")));
        Assert.Equal("sin cuota", turn.Error);
        Assert.Equal(new[] { "write_file" }, turn.Denied);
    }

    [Fact]
    public void CodexItemsAndTurns()
    {
        var parser = new CodexParser();
        Assert.Equal(new AgentEvent.Conversation("th"), Assert.Single(parser.Parse("{\"type\":\"thread.started\",\"thread_id\":\"th\"}")));
        var command = parser.Parse("{\"type\":\"item.completed\",\"item\":{\"id\":\"i1\",\"type\":\"command_execution\",\"command\":\"git status\",\"aggregated_output\":\"limpio\",\"exit_code\":1}}");
        Assert.Equal(2, command.Count);
        Assert.True(Assert.IsType<AgentEvent.ToolFinished>(command[1]).IsFailed);
        Assert.Equal(new AgentEvent.Text("Hecho"), Assert.Single(parser.Parse("{\"type\":\"item.completed\",\"item\":{\"id\":\"i2\",\"type\":\"agent_message\",\"text\":\"Hecho\"}}")));
        var failed = Assert.IsType<AgentEvent.TurnFinished>(Assert.Single(parser.Parse(
            "{\"type\":\"turn.failed\",\"error\":{\"message\":\"{\\\"error\\\":{\\\"message\\\":\\\"Límite alcanzado\\\"}}\"}}")));
        Assert.Equal("Límite alcanzado", failed.Error);
    }

    [Fact]
    public void BadLinesAreIgnored()
    {
        Assert.Empty(new ClaudeStreamParser().Parse("Update available! Run npm i -g"));
        Assert.Empty(new CodexParser().Parse("{not json"));
        Assert.Empty(new AgyParser().Parse(""));
    }
}

public class AgentReplyTests
{
    [Fact]
    public void EventsBuildTheReplyInOrder()
    {
        var reply = new AgentReply();
        reply.Apply(new AgentEvent.Text("Voy a revisar\n"), AgentKind.Claude);
        reply.Apply(new AgentEvent.ToolStarted("t1", "Bash", new Dictionary<string, string> { ["command"] = "dir" }), AgentKind.Claude);
        reply.Apply(new AgentEvent.ToolFinished("t1", "\u001B[32mok\u001B[0m\r\n", false), AgentKind.Claude);
        reply.Apply(new AgentEvent.Text("Listo."), AgentKind.Claude);
        reply.Apply(new AgentEvent.TurnFinished(new[] { "Write", "Write" }, null), AgentKind.Claude);

        Assert.Equal(3, reply.Steps.Count);
        Assert.Equal("Voy a revisar", reply.Steps[0].Text);
        Assert.Equal("Ejecutó un comando", reply.Steps[1].Text);
        Assert.Equal("dir", reply.Steps[1].Detail);
        Assert.Equal("ok\n", reply.Steps[1].Output);
        Assert.Equal(AgentStepState.Done, reply.Steps[1].State);
        Assert.Equal(new[] { "Write" }, reply.Denied);
        Assert.True(reply.IsFinished);
        Assert.Equal("Voy a revisarListo.", reply.Text);
    }

    [Fact]
    public void FailureEndsTheTurn()
    {
        var reply = new AgentReply();
        reply.Apply(new AgentEvent.ToolStarted("t1", "Read", new Dictionary<string, string>()), AgentKind.Codex);
        reply.Apply(new AgentEvent.Failed("se cerró"), AgentKind.Codex);
        Assert.Equal("se cerró", reply.Error);
        Assert.Equal(AgentStepState.Done, reply.Steps[0].State);
    }

    [Fact]
    public void RepliesSurviveJson()
    {
        var reply = new AgentReply();
        reply.Apply(new AgentEvent.Text("Hola"), AgentKind.Claude);
        reply.Finish();
        var json = System.Text.Json.JsonSerializer.Serialize(reply);
        var back = System.Text.Json.JsonSerializer.Deserialize<AgentReply>(json)!;
        Assert.Equal("Hola", back.Text);
        Assert.True(back.IsFinished);
    }

    [Theory]
    [InlineData("Read", "file_path", @"C:\proyecto\notas.md", "Leyó notas.md", "No pudo leer notas.md")]
    [InlineData("Write", "file_path", "/tmp/saludo.txt", "Creó saludo.txt", "No pudo crear saludo.txt")]
    [InlineData("Grep", "pattern", "TODO", "Buscó “TODO”", "No pudo buscar “TODO”")]
    [InlineData("WebFetch", "url", "https://learn.microsoft.com/windows", "Leyó una página learn.microsoft.com", "No pudo leer una página learn.microsoft.com")]
    [InlineData("mcp_custom_thing", "x", "y", "Usó mcp custom thing", "No pudo usar mcp custom thing")]
    public void ToolSummaries(string name, string key, string value, string text, string failed)
    {
        var summary = new ToolSummary(AgentKind.Claude, name, new Dictionary<string, string> { [key] = value });
        Assert.Equal(text, summary.Text);
        Assert.Equal(failed, summary.FailedText);
    }

    [Fact]
    public void CamelCaseToolNamesBecomeWords()
    {
        Assert.Equal("Usó notebook read", new ToolSummary(AgentKind.Claude, "NotebookRead", new Dictionary<string, string>()).Text);
    }

    [Fact]
    public void DeniedActionsInPlainWords()
    {
        Assert.Equal("crear o editar archivos", DeniedAction.Describe("Write"));
        Assert.Equal("ejecutar comandos", DeniedAction.Describe("Bash"));
        Assert.Equal("some tool", DeniedAction.Describe("some_tool"));
    }
}

public class AgentProcessTests
{
    [Fact]
    public void NpmShimsAreFound()
    {
        var existing = new HashSet<string> { Path.Combine(@"C:\npm", "claude.cmd") };
        var found = AgentProcess.Executable("claude", new[] { @"C:\Windows", @"C:\npm" }, existing.Contains);
        Assert.Equal(Path.Combine(@"C:\npm", "claude.cmd"), found);
        Assert.Null(AgentProcess.Executable("codex", new[] { @"C:\npm" }, existing.Contains));
    }

    [Fact]
    public void ExeWinsOverCmdInTheSameFolder()
    {
        var existing = new HashSet<string> { Path.Combine("bin", "agy.exe"), Path.Combine("bin", "agy.cmd") };
        Assert.Equal(Path.Combine("bin", "agy.exe"), AgentProcess.Executable("agy", new[] { "bin" }, existing.Contains));
    }

    [Fact]
    public void BatchFilesRunThroughCmd()
    {
        var info = AgentProcess.CreateStartInfo(@"C:\Users\Max\AppData\Roaming\npm\claude.cmd", new[] { "-p", "hola mundo" }, ".", Array.Empty<string>());
        Assert.EndsWith("cmd.exe", info.FileName);
        Assert.Equal("/d /s /c \"C:\\Users\\Max\\AppData\\Roaming\\npm\\claude.cmd -p \"hola mundo\"\"", info.Arguments);
        Assert.Equal("1", info.Environment["NO_COLOR"]);
        Assert.Equal("dumb", info.Environment["TERM"]);
        Assert.True(info.RedirectStandardInput && info.RedirectStandardOutput && info.RedirectStandardError);
    }

    [Fact]
    public void ScriptsRunThroughPowerShell()
    {
        var info = AgentProcess.CreateStartInfo(@"C:\tools\qwen.ps1", new[] { "-p", "hola" }, ".", new[] { @"C:\tools" });
        Assert.Equal("pwsh.exe", info.FileName);
        Assert.Equal(new[] { "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", @"C:\tools\qwen.ps1", "-p", "hola" }, info.ArgumentList);
        Assert.Equal(@"C:\tools", info.Environment["PATH"]);
    }

    [Fact]
    public void ExecutablesGetTheirArgumentsAsTheyAre()
    {
        var info = AgentProcess.CreateStartInfo(@"C:\bin\codex.exe", new[] { "exec", "--json", "a \"b\"" }, ".", Array.Empty<string>());
        Assert.Equal(@"C:\bin\codex.exe", info.FileName);
        Assert.Equal(new[] { "exec", "--json", "a \"b\"" }, info.ArgumentList);
    }

    [Fact]
    public void CmdQuoting()
    {
        Assert.Equal("plain", AgentProcess.QuoteForCmd("plain"));
        Assert.Equal("\"a & b\"", AgentProcess.QuoteForCmd("a & b"));
        Assert.Equal("\"di \"\"hola\"\"\"", AgentProcess.QuoteForCmd("di \"hola\""));
        Assert.Equal("\"\"", AgentProcess.QuoteForCmd(""));
    }
}

public class AgentChatTests
{
    [Fact]
    public void MissingCliFailsTheTurn()
    {
        var chat = new AgentChat(AgentKind.Codex, Guid.NewGuid(), ".", Array.Empty<string>(), InlineDispatcher.Instance,
            findExecutable: (_, _) => null);
        Assert.False(chat.IsInstalled);
        AgentReply? finished = null;
        chat.Send("hola", _ => { }, reply => finished = reply, ".", Array.Empty<string>());
        Assert.NotNull(finished);
        Assert.Equal("No se pudo abrir codex.", finished.Error);
        Assert.False(chat.IsResponding);
    }

    [Fact]
    public void PerTurnCliIsReadyWhenInstalled()
    {
        var chat = new AgentChat(AgentKind.Qwen, Guid.NewGuid(), ".", Array.Empty<string>(), InlineDispatcher.Instance,
            findExecutable: (_, _) => @"C:\npm\qwen.cmd");
        chat.WarmUp();
        Assert.True(chat.IsReady);
    }

    [Theory]
    [InlineData("Please log in to continue", true)]
    [InlineData("Do you trust the files in this folder? (y/n)", true)]
    [InlineData("Leyendo archivos…", false)]
    public void TerminalPrompts(string line, bool expected) => Assert.Equal(expected, AgentChat.IsTerminalPrompt(line));

    [Fact]
    public void ErrorsKeepTheMeaningfulLine()
    {
        var errors = "node:internal/modules/cjs/loader:1\n    at Module._load\nError: API key is required\n";
        Assert.Equal("Error: API key is required", AgentChat.Explain(errors, 1, AgentKind.Claude));
        Assert.Equal("claude se cerró (código 3).", AgentChat.Explain("", 3, AgentKind.Claude));
    }
}
