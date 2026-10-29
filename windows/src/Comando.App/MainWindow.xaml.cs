using System.ComponentModel;
using System.Diagnostics;
using Comando.Core.Models;
using Comando.Core.Services;
using Comando.Views;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.Graphics;

namespace Comando;

public sealed partial class MainWindow : Window
{
    private bool _closingConfirmed;

    public MainWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        AppWindow.Resize(new SizeInt32(1100, 720));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = 680;
            presenter.PreferredMinimumHeight = 440;
        }
        AppWindow.Closing += OnClosing;

        Controller.PropertyChanged += OnControllerChanged;
        ShowSelection();
    }

    public TerminalController Controller => App.Controller;

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
        if (!ReferenceEquals(SessionList.SelectedItem, Controller.SelectedSession))
        {
            SessionList.SelectedItem = Controller.SelectedSession;
        }
        Chat.Session = Controller.SelectedSession;
    }

    // Sidebar

    private void OnSessionSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (SessionList.SelectedItem is TerminalSession session && session != Controller.SelectedSession)
        {
            Controller.SelectedSession = session;
        }
    }

    private void OnNewSession(object sender, RoutedEventArgs e) => NewSession();

    private void NewSession()
    {
        Controller.CreateSession();
        Chat.FocusComposer();
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

    private async void OnDeleteSession(object sender, RoutedEventArgs e)
    {
        if (Session(sender) is not { } session) return;
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = $"¿Eliminar “{session.DisplayName}”?",
            Content = "Se borra su historial y se cierra lo que esté en curso. No se puede deshacer.",
            PrimaryButtonText = "Eliminar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
        {
            Controller.Delete(session);
        }
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
