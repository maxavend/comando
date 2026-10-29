namespace Comando.Core.Assistant;

public enum ModelAvailability
{
    Ready,
    /// <summary>Supported, but Windows still has to download or prepare it.</summary>
    NeedsSetup,
    /// <summary>This PC can't run it (not a Copilot+ PC, or an older Windows).</summary>
    NotSupported,
    DisabledByUser,
}

/// <summary>
/// The on-device model that writes the assistant's answers. On Windows it's
/// Phi Silica; tests use a fake. Nothing leaves the PC.
/// </summary>
public interface ILanguageModel
{
    ModelAvailability Availability { get; }

    /// <summary>Asks Windows to get the model ready. Returns whether it is.</summary>
    Task<bool> PrepareAsync();

    /// <summary>
    /// The model's answer to <paramref name="prompt"/>. <paramref name="progress"/>
    /// receives the text so far as it's written. Null when it couldn't answer.
    /// </summary>
    Task<string?> GenerateAsync(string prompt, IProgress<string>? progress = null, CancellationToken cancellation = default);
}

/// <summary>Used where no model exists: the guide and recipes still answer.</summary>
public sealed class NoLanguageModel : ILanguageModel
{
    public static readonly NoLanguageModel Instance = new();

    public ModelAvailability Availability => ModelAvailability.NotSupported;

    public Task<bool> PrepareAsync() => Task.FromResult(false);

    public Task<string?> GenerateAsync(string prompt, IProgress<string>? progress = null, CancellationToken cancellation = default) =>
        Task.FromResult<string?>(null);
}
