using Comando.Core.Language;
using Comando.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;

namespace Comando.Views;

/// <summary>
/// Recipes (Ctrl+K): common tasks explained in plain words. Pick one, fill
/// in what it needs, and run it or place it in the composer.
/// </summary>
internal sealed class RecipesDialog
{
    private readonly ContentDialog _dialog;
    private readonly AutoSuggestBox _search = new() { PlaceholderText = "Buscar una tarea: comprimir, espacio, puerto…", QueryIcon = new SymbolIcon(Symbol.Find) };
    private readonly ListView _list = new() { SelectionMode = ListViewSelectionMode.Single, Height = 320 };
    private readonly StackPanel _detail = new() { Spacing = 10 };
    private readonly Dictionary<string, TextBox> _fields = [];
    private readonly TerminalSession _session;
    private Recipe? _selected;

    public RecipesDialog(XamlRoot root, TerminalSession session)
    {
        _session = session;
        _search.TextChanged += (_, _) => Fill();
        _list.SelectionChanged += (_, _) => Select(_list.SelectedItem is ListViewItem { Tag: Recipe recipe } ? recipe : null);
        _list.IsItemClickEnabled = false;

        var content = new StackPanel { Spacing = 12, Width = 560 };
        content.Children.Add(_search);
        content.Children.Add(_list);
        content.Children.Add(_detail);

        _dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Recetas",
            Content = content,
            PrimaryButtonText = "Ejecutar",
            SecondaryButtonText = "Poner en el campo",
            CloseButtonText = "Cerrar",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false,
            IsSecondaryButtonEnabled = false,
        };
        _dialog.Resources["ContentDialogMaxWidth"] = 720.0;
        Fill();
    }

    public async Task ShowAsync()
    {
        _search.Loaded += (_, _) => _search.Focus(FocusState.Programmatic);
        var result = await _dialog.ShowAsync();
        if (_selected is null) return;
        var command = _selected.Command(Values());
        if (result == ContentDialogResult.Primary) App.Controller.Submit(command, App.Controller.IdleSession(_session));
        else if (result == ContentDialogResult.Secondary) App.Window?.Chat.Draft(command);
    }

    private IReadOnlyList<Recipe> AllRecipes() =>
        [.. App.Settings.SavedRecipes.Select(r => r.ToRecipe()), .. RecipeBook.All];

    private void Fill()
    {
        _list.Items.Clear();
        var query = _search.Text;
        var matches = AllRecipes().Where(r => r.Matches(query)).ToList();
        foreach (var group in matches.GroupBy(r => r.Category))
        {
            _list.Items.Add(new ListViewHeaderItem { Content = RecipeCategories.Title(group.Key) });
            foreach (var recipe in group) _list.Items.Add(Row(recipe));
        }
        if (matches.Count == 0)
        {
            _list.Items.Add(new ListViewItem { Content = "Ninguna receta coincide. Prueba con otras palabras, o pídelo al asistente.", IsEnabled = false });
        }
        var first = _list.Items.OfType<ListViewItem>().FirstOrDefault(item => item.Tag is Recipe);
        _list.SelectedItem = first;
    }

    private ListViewItem Row(Recipe recipe)
    {
        var grid = new Grid { ColumnSpacing = 12, Padding = new Thickness(0, 6, 0, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new FontIcon { Glyph = recipe.Glyph, FontSize = 16, VerticalAlignment = VerticalAlignment.Center });
        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = recipe.Title, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] });
        text.Children.Add(new TextBlock
        {
            Text = recipe.Detail,
            Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"],
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
            TextTrimming = TextTrimming.CharacterEllipsis,
        });
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        var item = new ListViewItem { Content = grid, Tag = recipe };
        if (recipe.Category == RecipeCategory.Mine)
        {
            var remove = new MenuFlyoutItem { Text = "Quitar de Mis recetas", Icon = new FontIcon { Glyph = "" } };
            remove.Click += (_, _) =>
            {
                App.Settings.RemoveRecipe(recipe.Id["saved-".Length..]);
                Fill();
            };
            var menu = new MenuFlyout();
            menu.Items.Add(remove);
            item.ContextFlyout = menu;
        }
        return item;
    }

    private void Select(Recipe? recipe)
    {
        _selected = recipe;
        _detail.Children.Clear();
        _fields.Clear();
        if (recipe is null)
        {
            Update();
            return;
        }
        foreach (var parameter in recipe.Parameters)
        {
            var field = new TextBox { Header = parameter.Label, PlaceholderText = parameter.Placeholder, Text = parameter.DefaultValue ?? "" };
            field.TextChanged += (_, _) => Update();
            _fields[parameter.Id] = field;
            if (parameter.Kind is RecipeParameterKind.Folder or RecipeParameterKind.File)
            {
                var row = new Grid { ColumnSpacing = 8 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.Children.Add(field);
                var choose = new Button { Content = "Elegir…", VerticalAlignment = VerticalAlignment.Bottom };
                choose.Click += async (_, _) => field.Text = await PickAsync(parameter.Kind) ?? field.Text;
                Grid.SetColumn(choose, 1);
                row.Children.Add(choose);
                _detail.Children.Add(row);
            }
            else
            {
                _detail.Children.Add(field);
            }
        }
        var preview = new TextBlock
        {
            FontFamily = (FontFamily)Application.Current.Resources["TerminalFontFamily"],
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true,
            Tag = "preview",
        };
        _detail.Children.Add(preview);
        Update();
    }

    private Dictionary<string, string> Values() => _fields.ToDictionary(pair => pair.Key, pair => pair.Value.Text);

    private void Update()
    {
        var ready = _selected is not null && _selected.IsComplete(Values());
        _dialog.IsPrimaryButtonEnabled = ready;
        _dialog.IsSecondaryButtonEnabled = _selected is not null;
        if (_detail.Children.OfType<TextBlock>().FirstOrDefault(t => (string?)t.Tag == "preview") is { } preview && _selected is not null)
        {
            preview.Text = _selected.Command(Values());
        }
    }

    private async Task<string?> PickAsync(RecipeParameterKind kind)
    {
        var handle = WinRT.Interop.WindowNative.GetWindowHandle(App.Window!);
        if (kind == RecipeParameterKind.Folder)
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, handle);
            return (await picker.PickSingleFolderAsync())?.Path;
        }
        var filePicker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.DocumentsLibrary };
        filePicker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(filePicker, handle);
        return (await filePicker.PickSingleFileAsync())?.Path;
    }
}
