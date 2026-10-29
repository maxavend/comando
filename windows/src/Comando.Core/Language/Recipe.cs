using Comando.Core.Assistant;

namespace Comando.Core.Language;

public enum RecipeCategory
{
    Files,
    System,
    Network,
    Development,
    /// <summary>Saved by the person from a command in the chat.</summary>
    Mine,
}

public static class RecipeCategories
{
    /// <summary>The categories of the built-in recipes, in the order they're shown.</summary>
    public static readonly RecipeCategory[] BuiltIn = [RecipeCategory.Files, RecipeCategory.System, RecipeCategory.Network, RecipeCategory.Development];

    public static string Title(RecipeCategory category) => category switch
    {
        RecipeCategory.Files => "Archivos y carpetas",
        RecipeCategory.System => "Tu PC",
        RecipeCategory.Network => "Red",
        RecipeCategory.Development => "Desarrollo",
        _ => "Mis recetas",
    };
}

public enum RecipeParameterKind
{
    Text,
    Number,
    Folder,
    File,
}

/// <summary>A value the recipe asks for before it builds its command.</summary>
public sealed record RecipeParameter(string Id, string Label, RecipeParameterKind Kind, string Placeholder, string? DefaultValue = null);

/// <summary>A common task, described in plain words, and the command that does it.</summary>
public sealed class Recipe
{
    private readonly Func<IReadOnlyDictionary<string, string>, string> _build;

    public Recipe(
        string id,
        string title,
        string detail,
        string glyph,
        RecipeCategory category,
        Func<IReadOnlyDictionary<string, string>, string> build,
        IReadOnlyList<string>? keywords = null,
        IReadOnlyList<RecipeParameter>? parameters = null,
        int? tint = null)
    {
        Id = id;
        Title = title;
        Detail = detail;
        Glyph = glyph;
        Category = category;
        Keywords = keywords ?? [];
        Parameters = parameters ?? [];
        Tint = tint;
        _build = build;
    }

    public string Id { get; }
    public string Title { get; }
    public string Detail { get; }

    /// <summary>A Segoe Fluent Icons glyph.</summary>
    public string Glyph { get; }

    public RecipeCategory Category { get; }

    /// <summary>Extra words people might search with.</summary>
    public IReadOnlyList<string> Keywords { get; }

    public IReadOnlyList<RecipeParameter> Parameters { get; }

    /// <summary>A saved recipe's color (a session color index); null for built-in ones.</summary>
    public int? Tint { get; }

    /// <summary>The command with the current values, or with placeholders for empty ones.</summary>
    public string Command(IReadOnlyDictionary<string, string>? values = null)
    {
        var filled = new Dictionary<string, string>();
        foreach (var parameter in Parameters)
        {
            var value = values is not null && values.TryGetValue(parameter.Id, out var given) ? given.Trim() : "";
            filled[parameter.Id] = value.Length == 0 ? parameter.DefaultValue ?? parameter.Placeholder : value;
        }
        return _build(filled);
    }

    /// <summary>Every parameter without a default has a value.</summary>
    public bool IsComplete(IReadOnlyDictionary<string, string>? values) =>
        Parameters.All(parameter => parameter.DefaultValue is not null
            || (values is not null && values.TryGetValue(parameter.Id, out var value) && value.Trim().Length > 0));

    /// <summary>Whether the recipe matches a search, ignoring case and accents.</summary>
    public bool Matches(string query)
    {
        query = query.Trim();
        if (query.Length == 0) return true;
        return new[] { Title, Detail }.Concat(Keywords).Any(text => TextNormalizer.Contains(text, query))
            || TextNormalizer.Contains(Command(), query);
    }
}
