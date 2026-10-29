using System.Text;
using Comando.Core.Language;
using Comando.Core.Shell;
using Comando.Core.Tools;

namespace Comando.Core.Assistant;

/// <summary>Everything the assistant knows about a request.</summary>
public sealed record AssistantRequest(
    string Text,
    string Directory,
    IReadOnlyList<string> Attachments,
    IReadOnlySet<string> KnownCommands,
    IReadOnlyList<(string Request, string Reply)> History);

/// <summary>
/// Answers requests in plain words. Questions about the app come from the
/// written guide, common tasks from the recipes, and the rest from the
/// on-device model, which only proposes: nothing runs without a click.
/// </summary>
public sealed class AssistantEngine
{
    private readonly ILanguageModel _model;

    public AssistantEngine(ILanguageModel model)
    {
        _model = model;
    }

    public async Task<AssistantReply> AnswerAsync(AssistantRequest request, IProgress<AssistantReply>? progress = null, CancellationToken cancellation = default)
    {
        var text = IntentDetector.Request(request.Text);
        if (TextNormalizer.IsGreeting(text))
        {
            return new AssistantReply { Explanation = "¡Hola! Dime qué quieres hacer, con tus palabras, y te propongo cómo. También puedes preguntarme qué hace Comando." };
        }
        if (TextNormalizer.IsThanks(text))
        {
            return new AssistantReply { Explanation = "De nada. Aquí estoy si necesitas otra cosa." };
        }
        if (AppGuide.TopicFor(text) is { } topic)
        {
            return Guide(AppGuide.Answer(topic));
        }

        var recipe = BestRecipe(text);
        if (recipe is not null && recipe.Parameters.Count == 0)
        {
            return FromRecipe(recipe);
        }

        if (_model.Availability is ModelAvailability.Ready or ModelAvailability.NeedsSetup)
        {
            var written = await WriteAsync(request, text, progress, cancellation);
            if (written is not null) return written;
        }

        if (recipe is not null) return FromRecipe(recipe);
        var related = RecipeBook.Search(text).Take(3).ToList();
        return new AssistantReply
        {
            Explanation = related.Count > 0
                ? "No tengo un modelo de IA en este PC para entender este pedido, pero estas recetas se parecen:"
                : "No tengo un modelo de IA en este PC para entender este pedido. Escribe el comando, o busca una receta con Ctrl+K.",
            Proposals = related.Select(r => new AssistantProposal { Command = r.Command(), Explanation = r.Title }).ToList(),
        };
    }

    // Guide and recipes

    private static AssistantReply Guide(GuideAnswer answer) => new()
    {
        Explanation = answer.Intro,
        Points = answer.Items.Select(item => new AssistantPoint { Glyph = item.Glyph, Title = item.Title, Detail = item.Detail }).ToList(),
    };

    private static AssistantReply FromRecipe(Recipe recipe) => new()
    {
        Explanation = recipe.Detail,
        Proposals = [new AssistantProposal { Command = recipe.Command(), Explanation = recipe.Title }],
    };

    /// <summary>The recipe that shares the most words with the request, when it shares enough.</summary>
    internal static Recipe? BestRecipe(string request)
    {
        var words = TextNormalizer.Keywords(request).Where(w => w.Length >= 3).ToHashSet();
        if (words.Count == 0) return null;
        Recipe? best = null;
        var bestScore = 0;
        foreach (var recipe in RecipeBook.All)
        {
            var recipeWords = TextNormalizer.Keywords(recipe.Title + " " + string.Join(' ', recipe.Keywords));
            var score = words.Count(recipeWords.Contains);
            if (score > bestScore)
            {
                best = recipe;
                bestScore = score;
            }
        }
        // Two words in common, or one when the request is that short.
        return bestScore >= Math.Min(2, words.Count) ? best : null;
    }

    // The model

    private async Task<AssistantReply?> WriteAsync(AssistantRequest request, string text, IProgress<AssistantReply>? progress, CancellationToken cancellation)
    {
        var partial = new Progress<string>(written =>
        {
            var parsed = Parse(written);
            parsed.IsWriting = true;
            progress?.Report(parsed);
        });
        var answer = await _model.GenerateAsync(Prompt(request, text), partial, cancellation);
        if (string.IsNullOrWhiteSpace(answer)) return null;
        var reply = Parse(answer);
        if (reply.Explanation is null && reply.Proposals.Count == 0) return null;
        Check(reply, request);
        return reply;
    }

    internal static string Prompt(AssistantRequest request, string text)
    {
        var prompt = new StringBuilder();
        prompt.AppendLine("Eres el asistente de Comando, una terminal para Windows que usa PowerShell 7.");
        prompt.AppendLine("Ayudas a personas que no conocen los comandos. Respondes en español, en pocas palabras, con tono directo.");
        prompt.AppendLine("Reglas: propones un solo comando de PowerShell en una línea. Nunca uses sudo ni Start-Process -Verb RunAs.");
        prompt.AppendLine("Para borrar archivos usa la función papelera (envía a la Papelera de reciclaje) en vez de Remove-Item.");
        prompt.AppendLine("Si la persona solo pregunta algo, responde sin comando.");
        prompt.AppendLine();
        prompt.AppendLine("Responde exactamente en este formato:");
        prompt.AppendLine("RESPUESTA: <una o dos frases>");
        prompt.AppendLine("COMANDO: <el comando, o NINGUNO>");
        prompt.AppendLine("QUE_HACE: <qué hace el comando, en palabras simples>");
        prompt.AppendLine();
        prompt.AppendLine($"Carpeta actual: {request.Directory}");
        var files = FolderSample(request.Directory);
        if (files.Length > 0) prompt.AppendLine($"Algunos archivos de la carpeta: {files}");
        if (request.Attachments.Count > 0) prompt.AppendLine($"Archivos adjuntos: {string.Join(", ", request.Attachments)}");
        var tools = new[] { "git", "ffmpeg", "magick", "pandoc", "yt-dlp", "node", "npm", "python", "py", "winget", "7z", "rg", "jq" }
            .Where(request.KnownCommands.Contains).ToList();
        if (tools.Count > 0) prompt.AppendLine($"Programas instalados que pueden servir: {string.Join(", ", tools)}");
        foreach (var (previous, reply) in request.History.TakeLast(3))
        {
            prompt.AppendLine($"Antes la persona pidió: {previous}. Respondiste: {reply}");
        }
        prompt.AppendLine();
        prompt.AppendLine($"Pedido: {text}");
        return prompt.ToString();
    }

    private static string FolderSample(string directory)
    {
        try
        {
            return string.Join(", ", System.IO.Directory.EnumerateFileSystemEntries(directory).Take(30).Select(Path.GetFileName));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return "";
        }
    }

    /// <summary>Reads the model's answer, tolerating missing labels and code fences.</summary>
    internal static AssistantReply Parse(string answer)
    {
        string? explanation = null, command = null, whatItDoes = null;
        var loose = new StringBuilder();
        foreach (var raw in answer.Replace("\r", "").Split('\n'))
        {
            var line = raw.Trim().Trim('`').Trim();
            if (line.Length == 0 || line.StartsWith("powershell", StringComparison.OrdinalIgnoreCase) && line.Length < 12) continue;
            if (Label(line, "RESPUESTA") is { } said) explanation = said;
            else if (Label(line, "COMANDO") is { } run) command = run;
            else if (Label(line, "QUE_HACE") is { } does) whatItDoes = does;
            else if (command is null) loose.Append(loose.Length > 0 ? " " : "").Append(line);
        }
        explanation ??= loose.Length > 0 ? loose.ToString() : null;
        var reply = new AssistantReply { Explanation = explanation };
        if (command is { Length: > 0 } && !command.Equals("NINGUNO", StringComparison.OrdinalIgnoreCase) && command != "-")
        {
            reply.Proposals.Add(new AssistantProposal { Command = command, Explanation = whatItDoes ?? "", IsGenerated = true });
        }
        return reply;
    }

    private static string? Label(string line, string label)
    {
        if (!line.StartsWith(label, StringComparison.OrdinalIgnoreCase)) return null;
        var rest = line[label.Length..].TrimStart();
        return rest.StartsWith(':') ? rest[1..].Trim().Trim('`').Trim() : null;
    }

    /// <summary>
    /// What the model wrote, made safe to show: no elevation, and a tool to
    /// install when the command needs one this PC doesn't have.
    /// </summary>
    internal static void Check(AssistantReply reply, AssistantRequest request)
    {
        reply.Proposals.RemoveAll(p => p.Command.Contains("sudo ", StringComparison.OrdinalIgnoreCase)
            || p.Command.Contains("-Verb RunAs", StringComparison.OrdinalIgnoreCase));
        foreach (var proposal in reply.Proposals)
        {
            var program = ShellWords.ProgramName(ShellWords.Split(proposal.Command).FirstOrDefault() ?? "");
            if (program.Length == 0 || IntentDetector.IsCmdlet(program) || request.KnownCommands.Contains(program) || Builtins.Contains(program)) continue;
            if (ToolCatalog.ProvidingCommand(program) is { } tool && reply.ToolsToInstall.All(t => t.Command != tool.InstallCommand))
            {
                reply.ToolsToInstall.Add(new AssistantProposal { Command = tool.InstallCommand, Explanation = $"{tool.Title}: {tool.Detail}" });
            }
        }
    }

    private static readonly HashSet<string> Builtins = new(StringComparer.OrdinalIgnoreCase)
    {
        "cd", "dir", "ls", "cls", "echo", "cat", "cp", "mv", "rm", "mkdir", "rmdir", "del", "copy", "move", "ren", "type", "where",
        "papelera", "explorer", "start", "notepad", "code", "%", "?", "foreach", "if", "for", "set-location", "write-output",
    };

    /// <summary>Whether a command changes files or the system, so a generated one asks before running.</summary>
    public static bool ChangesThings(string command)
    {
        var lower = command.ToLowerInvariant();
        string[] verbs = ["new-", "set-", "remove-", "move-", "rename-", "copy-", "clear-", "install", "uninstall", "update-", "stop-", "restart-", "papelera", "out-file", "add-content", "expand-archive", "compress-archive"];
        if (verbs.Any(lower.Contains)) return true;
        if (lower.Contains('>')) return true;
        var program = ShellWords.ProgramName(ShellWords.Split(command).FirstOrDefault() ?? "");
        return program is "rm" or "del" or "mv" or "move" or "cp" or "copy" or "ren" or "mkdir" or "md" or "winget" or "scoop" or "choco" or "npm" or "pip" or "pipx" or "uv" or "git" or "ffmpeg" or "magick";
    }

    /// <summary>A short title for the session from its first real request: “Comprimir video entrevista”.</summary>
    public static string? SessionTitle(string request)
    {
        var words = IntentDetector.Request(request)
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(w => w.Trim('¿', '?', '¡', '!', '.', ',', '"', '“', '”'))
            .Where(w => w.Length >= 3 && !TitleFiller.Contains(TextNormalizer.Normalize(w)))
            .Take(4)
            .ToList();
        if (words.Count < 2) return null;
        var title = string.Join(' ', words).ToLowerInvariant();
        return char.ToUpperInvariant(title[0]) + title[1..];
    }

    private static readonly HashSet<string> TitleFiller =
    [
        "quiero", "necesito", "puedes", "podrias", "como", "hago", "para", "por", "favor", "porfa", "que", "una", "uno", "los", "las",
        "del", "este", "esta", "esto", "estos", "estas", "mis", "sus", "con", "sin", "me", "ayudas", "ayuda", "dame", "hay", "todo", "todos",
    ];
}
