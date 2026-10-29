using System.Globalization;
using System.Text;

namespace Comando.Core.Assistant;

/// <summary>
/// Text as the assistant compares it: lowercase, without accents, so
/// “¿Qué es?” and “que es” read the same.
/// </summary>
public static class TextNormalizer
{
    /// <summary>Lowercase and without diacritics (“Ñandú” → “nandu”).</summary>
    public static string Normalize(string text)
    {
        var decomposed = text.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(character);
            }
        }
        return builder.ToString().Normalize(NormalizationForm.FormC);
    }

    /// <summary>Normalized, with everything that isn't a letter or digit turned into a space.</summary>
    public static string LettersAndDigits(string text)
    {
        var normalized = Normalize(text);
        var builder = new StringBuilder(normalized.Length);
        foreach (var character in normalized)
        {
            builder.Append(char.IsLetterOrDigit(character) ? character : ' ');
        }
        return builder.ToString();
    }

    /// <summary>The words that carry meaning, without articles or filler.</summary>
    public static HashSet<string> Keywords(string text) =>
        LettersAndDigits(text)
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(word => word.Length >= 2 && !Stopwords.Contains(word))
            .ToHashSet();

    /// <summary>Whether <paramref name="text"/> contains <paramref name="query"/>, ignoring case and accents.</summary>
    public static bool Contains(string text, string query) =>
        Normalize(text).Contains(Normalize(query), StringComparison.Ordinal);

    public static bool IsGreeting(string text) => IsOnly(GreetingPhrases, text);

    public static bool IsThanks(string text) => IsOnly(ThanksPhrases, text);

    /// <summary>“¿Qué es npm?”, but not “¿qué es lo que más pesa?”.</summary>
    public static bool AsksForMeaning(string text)
    {
        var words = Normalize(text).Trim('¿', '?', ' ');
        if (words.Contains("lo que")) return false;
        string[] prefixes = ["que es ", "que son ", "que significa", "para que sirve", "que hace ", "como funciona ", "explicame", "diferencia entre", "what is "];
        return prefixes.Any(words.StartsWith);
    }

    public static bool IsQuestion(string request)
    {
        var words = Normalize(request).Trim();
        string[] starts = ["que ", "como ", "cual ", "por que ", "cuando ", "donde "];
        return request.Contains('?') || starts.Any(words.StartsWith);
    }

    private static readonly string[] GreetingPhrases =
    [
        "que puedes hacer", "que sabes hacer", "en que me ayudas", "como funciona", "quien eres", "que eres",
        "buenos dias", "buenas tardes", "buenas noches", "que tal", "como estas", "como te va",
        "hola", "holi", "buenas", "hey", "hello", "hi", "ayuda", "ayudame",
    ];

    private static readonly string[] ThanksPhrases = ["muchas gracias", "gracias", "thanks", "genial", "perfecto", "buenisimo", "excelente"];

    /// <summary>Words that can sit around a greeting without asking for anything.</summary>
    private static readonly HashSet<string> Filler =
    [
        "y", "tu", "todo", "bien", "como", "que", "me", "te", "a", "ti", "por", "eso", "ok", "oye", "amigo", "crack",
        "de", "nuevo", "otra", "vez", "denuevo", "again", "mucho", "mil",
    ];

    private static readonly HashSet<string> Stopwords =
    [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "de", "del", "al", "en", "con", "por", "para", "que", "y", "o",
        "mi", "mis", "tu", "tus", "su", "sus", "me", "te", "se", "lo", "le", "es", "son", "esta", "este", "esto", "eso",
        "hay", "como", "cual", "quiero", "quisiera", "puedo", "puedes", "hacer", "hago", "ver", "muestra", "muestrame",
        "dime", "favor", "porfa", "hola", "aqui", "ahora", "todo", "todos", "mas", "muy", "the", "a", "an", "to", "of", "my",
    ];

    /// <summary>Only small talk: once the phrases and filler are gone, nothing is left.</summary>
    private static bool IsOnly(string[] phrases, string text)
    {
        var padded = " " + LettersOnly(Normalize(text)) + " ";
        var found = false;
        foreach (var phrase in phrases)
        {
            var key = $" {phrase} ";
            if (!padded.Contains(key)) continue;
            padded = padded.Replace(key, " ");
            found = true;
        }
        return found && padded.Split(' ', StringSplitOptions.RemoveEmptyEntries).All(Filler.Contains);
    }

    private static string LettersOnly(string text)
    {
        var builder = new StringBuilder(text.Length);
        foreach (var character in text) builder.Append(char.IsLetter(character) ? character : ' ');
        // Collapse runs of spaces so phrases match across punctuation.
        return string.Join(' ', builder.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }
}
