using Comando.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Comando.Views;

/// <summary>The sessions chosen in the sidebar, with Archivar and Eliminar for all of them.</summary>
public sealed partial class SelectionView : UserControl
{
    private IReadOnlyList<TerminalSession> _sessions = [];

    public SelectionView() => InitializeComponent();

    /// <summary>Archive (true) or bring back (false) the chosen sessions.</summary>
    public event Action<IReadOnlyList<TerminalSession>, bool>? ArchiveRequested;

    public event Action<IReadOnlyList<TerminalSession>>? DeleteRequested;

    /// <param name="checkboxes">Whether the list shows checkboxes (Seleccionar is on).</param>
    public void Show(IReadOnlyList<TerminalSession> sessions, bool checkboxes)
    {
        _sessions = sessions;
        Avatars.ItemsSource = sessions.Take(4).ToList();
        Heading.Text = sessions.Count switch
        {
            0 => "Ninguna sesión seleccionada",
            1 => "1 sesión seleccionada",
            var count => $"{count} sesiones seleccionadas",
        };
        Names.Text = NameList(sessions);
        Names.Visibility = Formatting.VisibleIf(sessions.Count > 0);

        // Bring back only when all of them are archived, as in the macOS app.
        var unarchive = sessions.Count > 0 && sessions.All(s => s.IsArchived);
        ArchiveLabel.Text = unarchive ? "Desarchivar" : "Archivar";
        ArchiveIcon.Glyph = unarchive ? "" : "";
        ArchiveButton.IsEnabled = DeleteButton.IsEnabled = sessions.Count > 0;

        Hint.Text = checkboxes
            ? "Marca las sesiones en la lista. Ctrl+A las marca todas."
            : "Ctrl+clic o Mayús+clic en la lista para elegir otras.";
    }

    private void OnArchive(object sender, RoutedEventArgs e) =>
        ArchiveRequested?.Invoke(_sessions, !_sessions.All(s => s.IsArchived));

    private void OnDelete(object sender, RoutedEventArgs e) => DeleteRequested?.Invoke(_sessions);

    /// <summary>“a, b, c y d”, or “a, b, c, d y 3 más”.</summary>
    private static string NameList(IReadOnlyList<TerminalSession> sessions)
    {
        var shown = sessions.Take(4).Select(s => s.DisplayName).ToList();
        var rest = sessions.Count - shown.Count;
        if (rest > 0) return string.Join(", ", shown) + $" y {rest} más";
        return shown.Count < 2 ? string.Join("", shown) : string.Join(", ", shown.Take(shown.Count - 1)) + " y " + shown[^1];
    }
}
