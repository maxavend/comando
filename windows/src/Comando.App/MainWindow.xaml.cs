using System.ComponentModel;
using System.Diagnostics;
using Comando.Core.Models;
using Comando.Core.Services;
using Microsoft.UI.Xaml.Media;
using Comando.Views;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.Graphics;
using Windows.System;

namespace Comando;

public sealed partial class MainWindow : Window
{
    private bool _closingConfirmed;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        FitToScreen();
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = 680;
            presenter.PreferredMinimumHeight = 440;
        }
        AppWindow.Closing += OnClosing;

        Controller.PropertyChanged += OnControllerChanged;
        Controller.CommandFinished += OnCommandFinished;
        App.Notifications.SessionRequested += id =>
        {
            if (Controller.Sessions.FirstOrDefault(s => s.Id == id) is { } session) Controller.SelectedSession = session;
            ShowChat();
            Activate();
        };
        App.Settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(AppSettings.Theme)) ApplyTheme();
        };
        Activated += (_, e) => _isActive = e.WindowActivationState != WindowActivationState.Deactivated;

        // Ctrl+, has no name in VirtualKey.
        var settingsShortcut = new KeyboardAccelerator { Key = (VirtualKey)188, Modifiers = VirtualKeyModifiers.Control };
        settingsShortcut.Invoked += OnSettingsAccelerator;
        Root.KeyboardAccelerators.Add(settingsShortcut);

        Tools.BackRequested += ShowChat;
        SettingsPage.BackRequested += ShowChat;
        SettingsPage.WelcomeRequested += () => _ = WelcomeDialog.ShowAsync(Content.XamlRoot);
        Selection.ArchiveRequested += Archive;
        Selection.DeleteRequested += sessions => _ = ConfirmDeleteAsync(sessions);
        Root.Loaded += OnRootLoaded;

        ApplyTheme();
        ShowSelection();
    }

    private bool _isActive = true;

    private async void OnRootLoaded(object sender, RoutedEventArgs e)
    {
        if (!App.Settings.HasSeenWelcome) await WelcomeDialog.ShowAsync(Content.XamlRoot);
        Chat.FocusComposer();
    }

    private void ApplyTheme()
    {
        Root.RequestedTheme = App.Settings.Theme switch
        {
            AppTheme.Light => ElementTheme.Light,
            AppTheme.Dark => ElementTheme.Dark,
            _ => ElementTheme.Default,
        };
    }

    private void OnCommandFinished(TerminalSession session, CommandEntry entry) =>
        App.Notifications.CommandFinished(session, entry, _isActive, Controller.SelectedSession == session && Chat.Visibility == Visibility.Visible);

    // Panes

    private void ShowChat()
    {
        if (Selection.Visibility == Visibility.Visible) EndSelecting();
        Chat.Visibility = Visibility.Visible;
        Tools.Visibility = Visibility.Collapsed;
        SettingsPage.Visibility = Visibility.Collapsed;
        Selection.Visibility = Visibility.Collapsed;
        Chat.FocusComposer();
    }

    private void ShowTools()
    {
        EndSelecting();
        Chat.Visibility = Visibility.Collapsed;
        SettingsPage.Visibility = Visibility.Collapsed;
        Selection.Visibility = Visibility.Collapsed;
        Tools.Visibility = Visibility.Visible;
        Tools.Show();
    }

    private void ShowSettings()
    {
        EndSelecting();
        Chat.Visibility = Visibility.Collapsed;
        Tools.Visibility = Visibility.Collapsed;
        Selection.Visibility = Visibility.Collapsed;
        SettingsPage.Visibility = Visibility.Visible;
        SettingsPage.Show();
    }

    /// <summary>Several sessions chosen, or checkboxes on: what can be done with them.</summary>
    private void ShowChosen()
    {
        Chat.Visibility = Visibility.Collapsed;
        Tools.Visibility = Visibility.Collapsed;
        SettingsPage.Visibility = Visibility.Collapsed;
        Selection.Visibility = Visibility.Visible;
        Selection.Show(Chosen(), IsSelecting);
    }

    private async void ShowRecipes()
    {
        if (Controller.SelectedSession is not { } session) return;
        ShowChat();
        await new RecipesDialog(Content.XamlRoot, session).ShowAsync();
    }

    private void OnShowTools(object sender, RoutedEventArgs e) => ShowTools();

    private void OnShowSettings(object sender, RoutedEventArgs e) => ShowSettings();

    private void OnShowRecipes(object sender, RoutedEventArgs e) => ShowRecipes();

    private void OnRecipesAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        ShowRecipes();
    }

    private void OnToolsAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        ShowTools();
    }

    private void OnSettingsAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        ShowSettings();
    }

    public TerminalController Controller => App.Controller;

    /// <summary>1100 × 720 at the screen's scale, smaller on small screens, centered.</summary>
    private void FitToScreen()
    {
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96.0;
        if (scale <= 0) scale = 1;
        var width = (int)Math.Min(1100 * scale, area.Width - 32 * scale);
        var height = (int)Math.Min(720 * scale, area.Height - 32 * scale);
        AppWindow.MoveAndResize(new RectInt32(area.X + (area.Width - width) / 2, area.Y + (area.Height - height) / 2, width, height));
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    private void OnControllerChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(TerminalController.SelectedSession):
                ShowSelection();
                break;
            case nameof(TerminalController.PendingCommand) when Controller.PendingCommand is { } pending:
                _ = ConfirmAsync(pending);
                break;
        }
    }

    private void ShowSelection()
    {
        // Another session opened (Ctrl+N, Ctrl+Tab, a notification…): back to one.
        if (IsSelecting || SessionList.SelectedItems.Count > 1)
        {
            ShowChat();
        }
        else if (!ReferenceEquals(SessionList.SelectedItem, Controller.SelectedSession))
        {
            SessionList.SelectedItem = Controller.SelectedSession;
        }
        Chat.Session = Controller.SelectedSession;
    }

    // Sidebar

    private void OnSessionSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingSelection) return;
        if (IsSelecting || SessionList.SelectedItems.Count > 1)
        {
            ShowChosen();
            return;
        }
        if (SessionList.SelectedItem is TerminalSession session && session != Controller.SelectedSession)
        {
            Controller.SelectedSession = session;
        }
        if (SessionList.SelectedItem is not null && Chat.Visibility != Visibility.Visible) ShowChat();
    }

    // Choosing several: Ctrl+clic and Mayús+clic always, checkboxes with Seleccionar.

    private bool _syncingSelection;

    private bool IsSelecting => SelectButton.IsChecked == true;

    private List<TerminalSession> Chosen() => SessionList.SelectedItems.OfType<TerminalSession>().ToList();

    private void OnSelectClick(object sender, RoutedEventArgs e)
    {
        if (IsSelecting)
        {
            SessionList.SelectionMode = ListViewSelectionMode.Multiple;
            ShowChosen();
        }
        else
        {
            ShowChat();
        }
    }

    /// <summary>Checkboxes off and the list back on the open session.</summary>
    private void EndSelecting()
    {
        _syncingSelection = true;
        SelectButton.IsChecked = false;
        SessionList.SelectionMode = ListViewSelectionMode.Extended;
        SessionList.SelectedItems.Clear();
        SessionList.SelectedItem = Controller.SelectedSession;
        _syncingSelection = false;
    }

    /// <summary>Archives from the selection panel or a menu on several: back to the chat first.</summary>
    private void Archive(IReadOnlyList<TerminalSession> sessions, bool archived)
    {
        ShowChat();
        Controller.SetArchived(sessions, archived);
    }

    /// <summary>The session a menu was opened on, or all the chosen ones when it is among them.</summary>
    private List<TerminalSession> Targets(object sender)
    {
        if (Session(sender) is not { } session) return [];
        var chosen = Chosen();
        return chosen.Count > 1 && chosen.Contains(session) ? chosen : [session];
    }

    private void OnNewSession(object sender, RoutedEventArgs e) => NewSession();

    private void NewSession()
    {
        Controller.CreateSession();
        ShowChat();
    }

    private void OnPaneToggleRequested(TitleBar sender, object args)
    {
        var hidden = Sidebar.Visibility == Visibility.Collapsed;
        Sidebar.Visibility = hidden ? Visibility.Visible : Visibility.Collapsed;
        SidebarColumn.Width = hidden ? new GridLength(300) : new GridLength(0);
    }

    private async void OnRenameSession(object sender, RoutedEventArgs e)
    {
        if (Session(sender) is not { } session) return;
        var field = new TextBox { Text = session.CustomName ?? session.DisplayName, PlaceholderText = session.DisplayName };
        field.SelectAll();
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Cambiar nombre",
            Content = field,
            PrimaryButtonText = "Guardar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            Controller.Rename(session, field.Text);
        }
    }

    private void OnToggleArchive(object sender, RoutedEventArgs e)
    {
        var sessions = Targets(sender);
        if (sessions.Count == 1 && Selection.Visibility != Visibility.Visible) Controller.SetArchived(sessions[0], !sessions[0].IsArchived);
        else if (sessions.Count > 0) Archive(sessions, !sessions.All(s => s.IsArchived));
    }

    private async void OnEditAppearance(object sender, RoutedEventArgs e)
    {
        if (Session(sender) is not { } session) return;
        var emoji = new TextBox { Header = "Emoji (opcional)", Text = session.Emoji ?? "", MaxLength = 8, PlaceholderText = "🚀" };
        var colors = new GridView { SelectionMode = ListViewSelectionMode.Single, Header = "Color" };
        foreach (var (name, _) in Formatting.SessionColors)
        {
            var index = colors.Items.Count;
            colors.Items.Add(new Microsoft.UI.Xaml.Shapes.Ellipse
            {
                Width = 28,
                Height = 28,
                Fill = Formatting.SessionBrush(index),
                Tag = index,
            });
            ToolTipService.SetToolTip((DependencyObject)colors.Items[index], name);
        }
        colors.SelectedIndex = session.ColorIndex;
        var panel = new StackPanel { Spacing = 16 };
        panel.Children.Add(emoji);
        panel.Children.Add(colors);
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = "Ícono y color",
            Content = panel,
            PrimaryButtonText = "Guardar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        session.Emoji = string.IsNullOrWhiteSpace(emoji.Text) ? null : emoji.Text.Trim();
        if (colors.SelectedIndex >= 0) session.ColorIndex = colors.SelectedIndex;
        Controller.SaveSoon();
    }

    private void OnTogglePin(object sender, RoutedEventArgs e)
    {
        if (Session(sender) is { } session) Controller.TogglePin(session);
    }

    private void OnRevealSession(object sender, RoutedEventArgs e)
    {
        if (Session(sender) is { } session) RevealInExplorer(Controller.Shell(session).Directory);
    }

    private void OnClearSession(object sender, RoutedEventArgs e)
    {
        if (Session(sender) is { } session) Controller.ClearHistory(session);
    }

    private void OnDeleteSession(object sender, RoutedEventArgs e) => _ = ConfirmDeleteAsync(Targets(sender));

    private async Task ConfirmDeleteAsync(IReadOnlyList<TerminalSession> sessions)
    {
        if (sessions.Count == 0) return;
        var one = sessions.Count == 1;
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = one ? $"¿Eliminar “{sessions[0].DisplayName}”?" : $"¿Eliminar {sessions.Count} sesiones?",
            Content = one
                ? "Se borra su historial y se cierra lo que esté en curso. No se puede deshacer."
                : "Se borra su historial y se cierra lo que esté en curso. No se puede deshacer. Si solo quieres sacarlas de la lista, archívalas.",
            PrimaryButtonText = one ? "Eliminar" : $"Eliminar {sessions.Count}",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        if (Selection.Visibility == Visibility.Visible) ShowChat();
        Controller.Delete(sessions);
    }

    private static TerminalSession? Session(object sender) => (sender as FrameworkElement)?.Tag as TerminalSession;

    public static void RevealInExplorer(string directory)
    {
        if (!Directory.Exists(directory)) return;
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{directory}\"") { UseShellExecute = true });
    }

    // Search

    private void OnSearchTextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (args.Reason != AutoSuggestionBoxTextChangeReason.UserInput) return;
        sender.ItemsSource = SearchResult.Find(Controller.Sessions, sender.Text);
    }

    private void OnSearchSuggestionChosen(AutoSuggestBox sender, AutoSuggestBoxSuggestionChosenEventArgs args)
    {
        if (args.SelectedItem is SearchResult result) Open(result);
    }

    private void OnSearchQuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        var result = args.ChosenSuggestion as SearchResult ?? SearchResult.Find(Controller.Sessions, args.QueryText).FirstOrDefault();
        if (result is not null) Open(result);
    }

    private void Open(SearchResult result)
    {
        Controller.SelectedSession = result.Session;
        ShowChat();
        SearchBox.Text = "";
        SearchBox.ItemsSource = null;
        if (result.Entry is { } entry) Chat.ScrollTo(entry);
    }

    // Keyboard

    private void OnNewSessionAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        NewSession();
    }

    private void OnSearchAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        SearchBox.Focus(FocusState.Keyboard);
    }

    private void OnClearAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        if (Controller.SelectedSession is { } session) Controller.ClearHistory(session);
    }

    private void OnNextSessionAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        Controller.SelectAdjacentSession(1);
    }

    private void OnPreviousSessionAccelerator(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        Controller.SelectAdjacentSession(-1);
    }

    // Risky commands

    private async Task ConfirmAsync(PendingCommand pending)
    {
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock { Text = pending.Risk.Explanation, TextWrapping = TextWrapping.Wrap });
        content.Children.Add(new TextBlock
        {
            Text = pending.Command,
            FontFamily = (Microsoft.UI.Xaml.Media.FontFamily)Application.Current.Resources["TerminalFontFamily"],
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true,
        });

        var recycle = pending.RecycleBinAlternative is not null;
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = pending.Risk.Title,
            Content = content,
            PrimaryButtonText = recycle ? "Enviar a la Papelera de reciclaje" : "Ejecutar de todos modos",
            SecondaryButtonText = recycle ? "Borrar para siempre" : "",
            CloseButtonText = "Cancelar",
            DefaultButton = recycle ? ContentDialogButton.Primary : ContentDialogButton.Close,
        };
        var answer = await dialog.ShowAsync();
        if (!ReferenceEquals(Controller.PendingCommand, pending)) return;
        switch (answer)
        {
            case ContentDialogResult.Primary when recycle:
                Controller.SendToRecycleBinInstead();
                break;
            case ContentDialogResult.Primary:
            case ContentDialogResult.Secondary:
                Controller.ConfirmPendingCommand();
                break;
            default:
                Controller.CancelPendingCommand();
                break;
        }
    }

    // Closing

    private async void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (!_closingConfirmed && Controller.HasRunningCommands)
        {
            args.Cancel = true;
            var dialog = new ContentDialog
            {
                XamlRoot = Content.XamlRoot,
                Title = "Hay comandos en curso",
                Content = "Si cierras Comando, se detienen.",
                PrimaryButtonText = "Cerrar de todos modos",
                CloseButtonText = "Cancelar",
                DefaultButton = ContentDialogButton.Close,
            };
            if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
            _closingConfirmed = true;
            Close();
            return;
        }
        Controller.TerminateAll();
    }
}
