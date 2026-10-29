using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Comando.Views;

/// <summary>What Comando does, shown the first time it opens and from Ajustes.</summary>
internal static class WelcomeDialog
{
    private static readonly (string Glyph, string Title, string Detail)[] Points =
    [
        ("", "Una terminal que conversa contigo",
            "Escribe un comando como si enviaras un mensaje. La respuesta llega en una burbuja, y si algo falla te explica por qué y qué probar."),
        ("", "Pídelo con tus palabras",
            "¿No sabes el comando? Escribe lo que quieres, como “comprime este video”, y el asistente te propone cómo hacerlo. En PCs Copilot+ usa Phi Silica, aquí en tu PC."),
        ("", "Siempre sabes dónde estás",
            "Arriba ves en qué carpeta estás. Ábrela en el Explorador de archivos con un clic, o arrastra una carpeta al chat para ir a ella."),
        ("", "Seguro por defecto",
            "Antes de un comando riesgoso te pide confirmación, y para borrar te ofrece la Papelera de reciclaje. Nada de lo que propone el asistente se ejecuta sin tu clic."),
        ("", "Atajos",
            "Ctrl+N nueva sesión · Ctrl+K recetas · Ctrl+F buscar · Ctrl+Mayús+I herramientas · Ctrl+, ajustes."),
    ];

    public static async Task ShowAsync(XamlRoot root)
    {
        var list = new StackPanel { Spacing = 18, MaxWidth = 520 };
        foreach (var (glyph, title, detail) in Points)
        {
            var grid = new Grid { ColumnSpacing = 16 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.Children.Add(new FontIcon
            {
                Glyph = glyph,
                FontSize = 24,
                Foreground = (Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"],
                VerticalAlignment = VerticalAlignment.Top,
            });
            var text = new StackPanel { Spacing = 2 };
            text.Children.Add(new TextBlock { Text = title, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
            text.Children.Add(new TextBlock
            {
                Text = detail,
                TextWrapping = TextWrapping.Wrap,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            });
            Grid.SetColumn(text, 1);
            grid.Children.Add(text);
            list.Children.Add(grid);
        }
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Te damos la bienvenida a Comando",
            Content = new ScrollViewer { Content = list },
            PrimaryButtonText = "Empezar",
            DefaultButton = ContentDialogButton.Primary,
        };
        await dialog.ShowAsync();
        App.Settings.HasSeenWelcome = true;
    }
}
