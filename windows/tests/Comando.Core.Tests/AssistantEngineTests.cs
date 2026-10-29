using Comando.Core.Assistant;
using Comando.Core.Models;
using Comando.Core.Services;
using Comando.Core.Shell;

namespace Comando.Core.Tests;

internal sealed class FakeModel(string answer) : ILanguageModel
{
    public List<string> Prompts { get; } = [];

    public ModelAvailability Availability => ModelAvailability.Ready;

    public Task<bool> PrepareAsync() => Task.FromResult(true);

    public Task<string?> GenerateAsync(string prompt, IProgress<string>? progress = null, CancellationToken cancellation = default)
    {
        Prompts.Add(prompt);
        progress?.Report(answer[..(answer.Length / 2)]);
        return Task.FromResult<string?>(answer);
    }
}

public class AssistantEngineTests
{
    private static AssistantRequest Request(string text) =>
        new(text, Path.GetTempPath(), [], new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "git" }, []);

    [Fact]
    public void ParsesTheLabeledAnswer()
    {
        var reply = AssistantEngine.Parse("RESPUESTA: Así se comprime.\nCOMANDO: `Compress-Archive -Path fotos -DestinationPath fotos.zip`\nQUE_HACE: Crea fotos.zip.");
        Assert.Equal("Así se comprime.", reply.Explanation);
        var proposal = Assert.Single(reply.Proposals);
        Assert.Equal("Compress-Archive -Path fotos -DestinationPath fotos.zip", proposal.Command);
        Assert.Equal("Crea fotos.zip.", proposal.Explanation);
        Assert.True(proposal.IsGenerated);
    }

    [Fact]
    public void NoCommandMeansJustAnAnswer()
    {
        var reply = AssistantEngine.Parse("RESPUESTA: Git guarda versiones de tus archivos.\nCOMANDO: NINGUNO\nQUE_HACE: -");
        Assert.Empty(reply.Proposals);
        Assert.Equal("Git guarda versiones de tus archivos.", reply.Explanation);
    }

    [Fact]
    public void UnlabeledTextBecomesTheExplanation()
    {
        var reply = AssistantEngine.Parse("Puedes usar Get-ChildItem para verlos.");
        Assert.Equal("Puedes usar Get-ChildItem para verlos.", reply.Explanation);
    }

    [Fact]
    public async Task GreetingsAnswerWithoutTheModel()
    {
        var model = new FakeModel("RESPUESTA: no");
        var reply = await new AssistantEngine(model).AnswerAsync(Request("hola"));
        Assert.NotNull(reply.Explanation);
        Assert.Empty(model.Prompts);
    }

    [Fact]
    public async Task QuestionsAboutTheAppUseTheGuide()
    {
        var model = new FakeModel("RESPUESTA: no");
        var reply = await new AssistantEngine(model).AnswerAsync(Request("¿para qué sirve Comando?"));
        Assert.NotEmpty(reply.Points);
        Assert.Empty(model.Prompts);
    }

    [Fact]
    public async Task OtherRequestsGoToTheModel()
    {
        var model = new FakeModel("RESPUESTA: Listo.\nCOMANDO: ffmpeg -i entrevista.mov entrevista.mp4\nQUE_HACE: Convierte el video.");
        var reply = await new AssistantEngine(model).AnswerAsync(Request("convierte entrevista.mov a mp4"));
        Assert.Single(model.Prompts);
        Assert.Contains("PowerShell", model.Prompts[0]);
        Assert.Equal("ffmpeg -i entrevista.mov entrevista.mp4", Assert.Single(reply.Proposals).Command);
        // ffmpeg isn't installed in the request: offer to install it.
        Assert.NotEmpty(reply.ToolsToInstall);
    }

    [Fact]
    public async Task ElevationIsNeverProposed()
    {
        var model = new FakeModel("RESPUESTA: Así.\nCOMANDO: Start-Process pwsh -Verb RunAs\nQUE_HACE: Abre como administrador.");
        var reply = await new AssistantEngine(model).AnswerAsync(Request("abre powershell como administrador"));
        Assert.Empty(reply.Proposals);
    }

    [Fact]
    public void GeneratedCommandsThatChangeThingsAreRecognized()
    {
        Assert.True(AssistantEngine.ChangesThings("Rename-Item a.txt b.txt"));
        Assert.True(AssistantEngine.ChangesThings("winget install Gyan.FFmpeg"));
        Assert.True(AssistantEngine.ChangesThings("Get-Process > procesos.txt"));
        Assert.False(AssistantEngine.ChangesThings("Get-ChildItem -Force"));
    }

    [Fact]
    public void SessionTitlesComeFromTheRequest()
    {
        Assert.Equal("Comprimir video entrevista", AssistantEngine.SessionTitle("quiero comprimir el video de la entrevista"));
        Assert.Null(AssistantEngine.SessionTitle("hola"));
    }
}

public class AssistantControllerTests
{
    [Fact]
    public void PlainWordsGoToTheAssistant()
    {
        var terminal = new FakeTerminal();
        var store = new SessionStore(Path.Combine(Path.GetTempPath(), $"comando-{Guid.NewGuid()}.json"));
        var controller = new TerminalController(() => terminal, InlineDispatcher.Instance, store)
        {
            Assistant = new AssistantEngine(new FakeModel("RESPUESTA: Así se ve.\nCOMANDO: Get-ChildItem\nQUE_HACE: Lista los archivos.")),
        };
        var session = controller.SelectedSession!;
        controller.Shell(session);
        terminal.Prompt(0, @"C:\Users\max");

        controller.Send("muéstrame qué archivos hay en esta carpeta", session);

        var entry = Assert.Single(session.Entries);
        Assert.Equal(EntryKind.Assistant, entry.Kind);
        Assert.Empty(terminal.Written);
    }

    [Fact]
    public void CommandsGoToTheShell()
    {
        var terminal = new FakeTerminal();
        var store = new SessionStore(Path.Combine(Path.GetTempPath(), $"comando-{Guid.NewGuid()}.json"));
        var controller = new TerminalController(() => terminal, InlineDispatcher.Instance, store);
        var session = controller.SelectedSession!;
        controller.Shell(session);
        terminal.Prompt(0, @"C:\Users\max");

        controller.Send("Get-ChildItem -Force", session);

        Assert.Equal(EntryKind.Command, Assert.Single(session.Entries).Kind);
        Assert.Single(terminal.Written);
    }
}

public class TypoDetectorTests
{
    [Theory]
    [InlineData("gti status")]
    [InlineData("gut push")]
    [InlineData("npn install")]
    [InlineData("wignet upgrade --all")]
    public void MistypedCommandsAreRecognized(string text) => Assert.True(Comando.Core.Language.TypoDetector.IsMistypedCommand(text));

    [Theory]
    [InlineData("sube esto a github")]
    [InlineData("comprime este video")]
    [InlineData("git status")]
    [InlineData("gti")]
    public void OtherTextIsNot(string text) => Assert.False(Comando.Core.Language.TypoDetector.IsMistypedCommand(text));
}
