using Comando.Core.Assistant;
using Comando.Core.Language;

namespace Comando.Core.Tests;

public class RecipeTests
{
    [Fact]
    public void EveryRecipeBuildsACommandWithPlaceholders()
    {
        foreach (var recipe in RecipeBook.All)
        {
            Assert.False(string.IsNullOrWhiteSpace(recipe.Command()), recipe.Id);
        }
    }

    [Fact]
    public void IdsAreUnique() =>
        Assert.Equal(RecipeBook.All.Count, RecipeBook.All.Select(recipe => recipe.Id).Distinct().Count());

    [Fact]
    public void ParametersAreQuotedForPowerShell()
    {
        var recipe = RecipeBook.Find("mkdir")!;
        Assert.Equal("New-Item -ItemType Directory -Name 'Mis fotos'", recipe.Command(new Dictionary<string, string> { ["name"] = "Mis fotos" }));
    }

    [Fact]
    public void DefaultsMakeARecipeComplete()
    {
        Assert.True(RecipeBook.Find("serve")!.IsComplete(new Dictionary<string, string>()));
        Assert.False(RecipeBook.Find("port")!.IsComplete(new Dictionary<string, string>()));
        Assert.True(RecipeBook.Find("port")!.IsComplete(new Dictionary<string, string> { ["port"] = "3000" }));
    }

    [Fact]
    public void PortKeepsOnlyDigits() =>
        Assert.Contains("-LocalPort 3000 ", RecipeBook.Find("port")!.Command(new Dictionary<string, string> { ["port"] = "30a00" }));

    [Fact]
    public void ZipNamesTheArchiveAfterTheFolder() =>
        Assert.Equal("Compress-Archive -Path C:\\fotos\\viaje -DestinationPath viaje.zip",
            RecipeBook.Find("zip")!.Command(new Dictionary<string, string> { ["folder"] = @"C:\fotos\viaje" }));

    [Fact]
    public void SearchIgnoresCaseAndAccents()
    {
        Assert.Contains(RecipeBook.Search("BATERIA"), recipe => recipe.Id == "battery");
        Assert.Contains(RecipeBook.Search("versión"), recipe => recipe.Id == "winver");
        Assert.Contains(RecipeBook.Search("Get-PSDrive"), recipe => recipe.Id == "df");
        Assert.Equal(RecipeBook.All.Count, RecipeBook.Search("  ").Count);
    }
}

public class ErrorExplainerTests
{
    private static readonly string[] Known = ["git", "npm", "node", "winget", "Get-ChildItem"];

    private static CommandHint? Hint(string command, string output, int? code = 1) =>
        ErrorExplainer.Hint(command, output, code, () => Known);

    [Fact]
    public void SuccessAndCtrlCHaveNoHint()
    {
        Assert.Null(Hint("gti status", "is not recognized as a name of a cmdlet", 0));
        Assert.Null(Hint("gti status", "is not recognized as a name of a cmdlet", ErrorExplainer.InterruptedStatus));
        Assert.Null(Hint("gti status", "is not recognized as a name of a cmdlet", null));
    }

    [Fact]
    public void TyposSuggestTheClosestCommand()
    {
        var hint = Hint("gti status", "gti: The term 'gti' is not recognized as a name of a cmdlet, function, script file, or executable program.");
        Assert.NotNull(hint);
        Assert.Equal("git status", hint.Suggestion);
    }

    [Fact]
    public void SpanishPowerShellIsUnderstood()
    {
        var hint = Hint("nmp install", "El término 'nmp' no se reconoce como nombre de un cmdlet, función, archivo de script o programa ejecutable.");
        Assert.Equal("npm install", hint?.Suggestion);
    }

    [Fact]
    public void MacCommandsPointToTheirWindowsEquivalent()
    {
        var hint = Hint("grep TODO notas.txt", "grep: The term 'grep' is not recognized as a name of a cmdlet");
        Assert.Equal("Select-String TODO notas.txt", hint?.Suggestion);
    }

    [Fact]
    public void ExecutionPolicyOffersTheFix()
    {
        var hint = Hint(".\\build.ps1", "File C:\\x\\build.ps1 cannot be loaded because running scripts is disabled on this system.");
        Assert.Equal("Set-ExecutionPolicy -Scope CurrentUser RemoteSigned", hint?.Suggestion);
    }

    [Theory]
    [InlineData("Remove-Item x", "Remove-Item: Access to the path 'C:\\x' is denied.")]
    [InlineData("Get-Content nada.txt", "Get-Content: Cannot find path 'C:\\nada.txt' because it does not exist.")]
    [InlineData("echo 'hola", "ParserError: The string is missing the terminator: '.")]
    [InlineData("git status", "fatal: not a git repository (or any of the parent directories): .git")]
    [InlineData("npm run dev", "npm ERR! enoent Could not read package.json")]
    [InlineData("Remove-Item informe.docx", "The process cannot access the file because it is being used by another process.")]
    public void CommonErrorsAreExplained(string command, string output) => Assert.NotNull(Hint(command, output));

    [Fact]
    public void PortInUseSuggestsFindingTheProgram()
    {
        var hint = Hint("npm run dev", "Error: listen EADDRINUSE: address already in use :::3000");
        Assert.Contains("-LocalPort 3000", hint?.Suggestion);
    }

    [Fact]
    public void EditDistanceCountsSwapsAsOne()
    {
        Assert.Equal(1, ErrorExplainer.EditDistance("gti", "git"));
        Assert.Equal(0, ErrorExplainer.EditDistance("npm", "npm"));
        Assert.Equal(3, ErrorExplainer.EditDistance("", "abc"));
    }
}

public class CommandExplainerTests
{
    [Fact]
    public void TokensKeepQuotesAndConnectors() =>
        Assert.Equal(new[] { "Get-ChildItem", "'mis fotos'", "|", "Select-Object", "-First", "3" },
            CommandExplainer.Tokens("Get-ChildItem 'mis fotos' | Select-Object -First 3"));

    [Fact]
    public void BackslashesStayInPaths() =>
        Assert.Equal(new[] { "cd", "C:\\Users\\ana" }, CommandExplainer.Tokens("cd C:\\Users\\ana"));

    [Fact]
    public void AliasesAreDescribedLikeTheirCmdlet()
    {
        Assert.Equal("Listar archivos", CommandGlossary.Describe("ls"));
        Assert.Equal("Listar archivos", CommandGlossary.Describe("Get-ChildItem -Force"));
        Assert.Equal("Guardar los cambios", CommandGlossary.Describe("git commit -m 'x'"));
        Assert.Equal("Actualizar programas", CommandGlossary.Describe("winget upgrade --all"));
        Assert.Null(CommandGlossary.Describe("programa-inventado"));
    }

    [Fact]
    public void PartsExplainOptionsAndArguments()
    {
        var parts = CommandExplainer.Parts("Remove-Item .\\build -Recurse -Force");
        Assert.Equal(4, parts.Count);
        Assert.Equal("Eliminar archivos", parts[0].Explanation);
        Assert.Equal("Un archivo o carpeta", parts[1].Explanation);
        Assert.Equal("incluye carpetas y su contenido", parts[2].Explanation);
    }

    [Fact]
    public void OptionPrefixesAreUnderstood() =>
        Assert.Equal("incluye subcarpetas", CommandExplainer.Parts("gci -Rec")[1].Explanation);

    [Fact]
    public void CombinedGitFlagsAreSplit() =>
        Assert.Equal("-f: sin preguntar · -d: incluye carpetas", CommandExplainer.Parts("git clean -fd")[2].Explanation);

    [Fact]
    public void ConnectorsResetTheProgram()
    {
        var parts = CommandExplainer.Parts("git status && npm test");
        Assert.Equal("Si funciona, ejecuta lo que sigue", parts[2].Explanation);
        Assert.Equal("Gestionar paquetes de Node.js", parts[3].Explanation);
        Assert.Equal("Ejecutar las pruebas", parts[4].Explanation);
    }
}

public class OutputLinkerTests
{
    [Fact]
    public void UrlsAreFoundWithoutTrailingPunctuation()
    {
        var link = Assert.Single(OutputLinker.Urls("Abre https://example.com/docs."));
        Assert.Equal("https://example.com/docs", link.Target);
        Assert.Equal(5, link.Start);
    }

    [Fact]
    public void LocalServerAddressIsFound()
    {
        Assert.Equal(new Uri("http://localhost:5173/"), OutputLinker.FirstLocalUrl("  ➜  Local:   http://localhost:5173/"));
        Assert.Equal("localhost", OutputLinker.FirstLocalUrl("Serving on http://0.0.0.0:8000")?.Host);
        Assert.Null(OutputLinker.FirstLocalUrl("Docs at https://vitejs.dev"));
    }

    [Fact]
    public void AbsoluteWindowsPathsAreFound()
    {
        var links = OutputLinker.AbsolutePaths(@"Guardado en C:\Users\ana\informe.pdf.", path => path == @"C:\Users\ana\informe.pdf");
        Assert.Equal(@"C:\Users\ana\informe.pdf", Assert.Single(links).Target);
    }

    [Fact]
    public void NamesWithSpacesInAListing()
    {
        var entries = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Mis fotos", "notas.txt" };
        var links = OutputLinker.Names("d----   28-10-2026   10:00         Mis fotos", entries);
        Assert.Equal("Mis fotos", Assert.Single(links).Target);
    }

    [Fact]
    public void ListedFolderOnlyForPlainListings()
    {
        var folder = Path.GetTempPath();
        Assert.Equal(folder, OutputLinker.ListedFolder("Get-ChildItem", folder));
        Assert.Equal(folder, OutputLinker.ListedFolder("ls -Force", folder));
        Assert.Null(OutputLinker.ListedFolder("ls -Recurse", folder));
        Assert.Null(OutputLinker.ListedFolder("git status", folder));
    }
}

public class ProgressParserTests
{
    [Fact]
    public void PercentagesAreRead()
    {
        var progress = ProgressParser.Parse("Descargando  [=====>     ] 45%");
        Assert.NotNull(progress);
        Assert.Equal(0.45, progress.Fraction, 3);
        Assert.Equal("Descargando 45%", progress.Label);
    }

    [Fact]
    public void CountsNeedABarOrTheWordProgress()
    {
        Assert.Equal(0.25, ProgressParser.Parse("[12/48] compilando")?.Fraction ?? 0, 3);
        Assert.Null(ProgressParser.Parse("12/48 archivos"));
        Assert.Null(ProgressParser.Parse("   "));
    }
}

public class AssistantTextTests
{
    private static readonly IReadOnlySet<string> Known = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "git", "npm", "winget", "ffmpeg" };

    [Theory]
    [InlineData("git status")]
    [InlineData("Get-ChildItem -Force")]
    [InlineData("ConvertTo-Json")]
    [InlineData("cd ..")]
    [InlineData("dir")]
    [InlineData("$x = 5")]
    [InlineData(".\\build.ps1")]
    [InlineData("cosa | otra")]
    [InlineData("python3 -m http.server")]
    public void CommandsGoToPowerShell(string text) => Assert.False(IntentDetector.IsPlainLanguage(text, Known));

    [Theory]
    [InlineData("sube mis cambios a GitHub")]
    [InlineData("comprime esta carpeta en un zip")]
    [InlineData("? git que hace")]
    [InlineData("hola")]
    [InlineData("gracias")]
    [InlineData("atajos")]
    public void PlainWordsGoToTheAssistant(string text) => Assert.True(IntentDetector.IsPlainLanguage(text, Known));

    [Fact]
    public void RequestDropsTheQuestionMark() => Assert.Equal("git que hace", IntentDetector.Request("  ? git que hace"));

    [Fact]
    public void NormalizeRemovesAccentsAndCase() => Assert.Equal("que es la nandu", TextNormalizer.Normalize("¿Qué es la Ñandú".TrimStart('¿')));

    [Fact]
    public void GreetingsAndThanks()
    {
        Assert.True(TextNormalizer.IsGreeting("¡Hola! ¿Qué tal?"));
        Assert.True(TextNormalizer.IsThanks("muchas gracias"));
        Assert.False(TextNormalizer.IsGreeting("hola, instala ffmpeg"));
    }

    [Fact]
    public void KeywordsDropFiller()
    {
        var keywords = TextNormalizer.Keywords("Quiero que comprimas el vídeo");
        Assert.Contains("comprimas", keywords);
        Assert.Contains("video", keywords);
        Assert.DoesNotContain("el", keywords);
        Assert.DoesNotContain("quiero", keywords);
    }

    [Fact]
    public void ValuesOfParametersAreNamed()
    {
        var parts = CommandExplainer.Parts("Remove-Item -Recurse build");
        Assert.Equal("Un dato para el comando", parts[2].Explanation);
        Assert.Equal("El valor de la opción anterior", CommandExplainer.Parts("Get-ChildItem -Filter informe")[2].Explanation);
    }

    [Theory]
    [InlineData("¿Para qué sirve Comando?", GuideTopic.Overview)]
    [InlineData("¿Qué atajos hay?", GuideTopic.Shortcuts)]
    [InlineData("¿cómo cambio de carpeta?", GuideTopic.Folders)]
    [InlineData("¿Es privado?", GuideTopic.Privacy)]
    [InlineData("sesiones", GuideTopic.Sessions)]
    public void GuideTopicsAreRecognized(string request, GuideTopic topic) => Assert.Equal(topic, AppGuide.TopicFor(request));

    [Theory]
    [InlineData("¿para qué sirve git?")]
    [InlineData("instala ffmpeg")]
    [InlineData("nueva sesión")]
    public void OtherRequestsAreNotAboutTheApp(string request) => Assert.Null(AppGuide.TopicFor(request));

    [Fact]
    public void EveryTopicHasAnAnswer()
    {
        foreach (var topic in Enum.GetValues<GuideTopic>())
        {
            var answer = AppGuide.Answer(topic);
            Assert.NotEmpty(answer.Items);
            Assert.Equal(4, answer.FollowUps.Count);
        }
    }
}
