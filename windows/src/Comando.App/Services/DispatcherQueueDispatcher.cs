using Comando.Core.Shell;
using Microsoft.UI.Dispatching;

namespace Comando.Services;

/// <summary>Moves shell events onto the UI thread, in the order they arrived.</summary>
public sealed class DispatcherQueueDispatcher(DispatcherQueue queue) : IDispatcher
{
    public void Post(Action action) => queue.TryEnqueue(() => action());
}
