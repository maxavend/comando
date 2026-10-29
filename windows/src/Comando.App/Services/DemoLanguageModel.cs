using Comando.Core.Assistant;

namespace Comando.Services;

/// <summary>
/// Stands in for Phi Silica when COMANDO_DEMO_MODEL is set, so the CI can show
/// the assistant thinking and writing on a PC without an NPU. Never used otherwise.
/// </summary>
public sealed class DemoLanguageModel : ILanguageModel
{
    private const string Answer =
        "RESPUESTA: Para pasar el video a MP4 sin perder calidad, usa ffmpeg.\n" +
        "COMANDO: ffmpeg -i entrevista.mov -c:v libx264 -crf 20 -c:a aac entrevista.mp4\n" +
        "QUE_HACE: Crea entrevista.mp4 con video H.264 y audio AAC; el original no cambia.";

    public static bool IsRequested => Environment.GetEnvironmentVariable("COMANDO_DEMO_MODEL") == "1";

    public ModelAvailability Availability => ModelAvailability.Ready;

    public Task<bool> PrepareAsync() => Task.FromResult(true);

    public async Task<string?> GenerateAsync(string prompt, IProgress<string>? progress = null, CancellationToken cancellation = default)
    {
        // A moment to think, then the words arrive a few at a time.
        await Task.Delay(TimeSpan.FromSeconds(4), cancellation);
        var words = Answer.Split(' ');
        var written = "";
        foreach (var word in words)
        {
            written += (written.Length > 0 ? " " : "") + word;
            progress?.Report(written);
            await Task.Delay(120, cancellation);
        }
        return Answer;
    }
}
