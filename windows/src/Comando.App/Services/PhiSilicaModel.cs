using Comando.Core.Assistant;
using Microsoft.Windows.AI;
using Microsoft.Windows.AI.Text;

namespace Comando.Services;

/// <summary>
/// Phi Silica, Windows' on-device language model (Copilot+ PCs). Everything
/// runs on the PC; on other PCs the assistant answers from its guide and
/// recipes only.
/// </summary>
public sealed class PhiSilicaModel : ILanguageModel
{
    private LanguageModel? _model;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public ModelAvailability Availability
    {
        get
        {
            try
            {
                return LanguageModel.GetReadyState() switch
                {
                    AIFeatureReadyState.Ready => ModelAvailability.Ready,
                    AIFeatureReadyState.NotReady => ModelAvailability.NeedsSetup,
                    AIFeatureReadyState.DisabledByUser => ModelAvailability.DisabledByUser,
                    _ => ModelAvailability.NotSupported,
                };
            }
            catch (Exception)
            {
                // Unpackaged, older Windows App SDK runtime, or no NPU.
                return ModelAvailability.NotSupported;
            }
        }
    }

    public async Task<bool> PrepareAsync()
    {
        try
        {
            if (LanguageModel.GetReadyState() == AIFeatureReadyState.NotReady)
            {
                await LanguageModel.EnsureReadyAsync();
            }
            return LanguageModel.GetReadyState() == AIFeatureReadyState.Ready;
        }
        catch (Exception)
        {
            return false;
        }
    }

    public async Task<string?> GenerateAsync(string prompt, IProgress<string>? progress = null, CancellationToken cancellation = default)
    {
        // One request at a time: the model is shared by every session.
        await _gate.WaitAsync(cancellation);
        try
        {
            if (Availability != ModelAvailability.Ready && !await PrepareAsync()) return null;
            _model ??= await LanguageModel.CreateAsync();
            var operation = _model.GenerateResponseAsync(prompt);
            if (progress is not null)
            {
                var text = "";
                operation.Progress = (_, delta) =>
                {
                    text += delta;
                    progress.Report(text);
                };
            }
            using var registration = cancellation.Register(() => operation.Cancel());
            var result = await operation;
            return result.Status == LanguageModelResponseStatus.Complete ? result.Text : null;
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            _gate.Release();
        }
    }
}
