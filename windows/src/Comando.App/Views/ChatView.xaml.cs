using System.Collections.Specialized;
using System.ComponentModel;
using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Shell;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using Windows.UI.Core;

namespace Comando.Views;

/// <summary>One session's conversation: its commands and answers, and the field to write the next one.</summary>
public sealed partial class ChatView : UserControl
{
    /// <summary>Approximate cell size of the terminal font, to tell the shell how wide the chat is.</summary>
    private const double CellWidth = 7.8;
    private const double CellHeight = 17;

    private TerminalSession? _session;
    private ShellSession? _shell;

    public ChatView()
    {
        InitializeComponent();
    }

    public TerminalSession? Session
    {
        get => _session;
        set
        {
            if (ReferenceEquals(_session, value)) return;
            if (_session is not null)
            {
                _session.PropertyChanged -= OnSessionChanged;
                _session.Entries.CollectionChanged -= OnEntriesChanged;
            }
            if (_shell is not null) _shell.PropertyChanged -= OnShellChanged;

            _session = value;
            _shell = value is null ? null : App.Controller.Shell(value);
            EntryList.ItemsSource = value?.Entries;

            if (_session is not null)
            {
                _session.PropertyChanged += OnSessionChanged;
                _session.Entries.CollectionChanged += OnEntriesChanged;
            }
            if (_shell is not null) _shell.PropertyChanged += OnShellChanged;

            UpdateHeader();
            UpdateEmptyState();
            UpdateShellState();
            ApplyChatSize();
            if (value?.Entries.LastOrDefault() is { } last) EntryList.ScrollIntoView(last);
        }
    }

    public void FocusComposer() => Composer.Focus(FocusState.Programmatic);

    public void ScrollTo(CommandEntry entry)
    {
        EntryList.ScrollIntoView(entry, ScrollIntoViewAlignment.Leading);
    }

    // State

    private void OnSessionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(TerminalSession.DisplayName) or nameof(TerminalSession.Directory)) UpdateHeader();
    }

    private void OnEntriesChanged(object? sender, NotifyCollectionChangedEventArgs e) => UpdateEmptyState();

    private void OnShellChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(ShellSession.Phase)) UpdateShellState();
        if (e.PropertyName is nameof(ShellSession.Directory)) UpdateHeader();
    }

    private void UpdateHeader()
    {
        TitleText.Text = _session?.DisplayName ?? "";
        FolderText.Text = _shell?.Directory ?? _session?.Directory ?? "";
    }

    private void UpdateEmptyState()
    {
        EmptyState.Visibility = Formatting.VisibleIf(_session is { Entries.Count: 0 });
    }

    private void UpdateShellState()
    {
        var busy = _shell?.IsBusy ?? false;
        SendButton.Visibility = Formatting.VisibleIf(!busy);
        StopButton.Visibility = Formatting.VisibleIf(busy);
        Composer.PlaceholderText = busy ? "Escribe para responderle al programa" : "Escribe un comando";

        switch (_shell?.Phase)
        {
            case ShellPhase.Exited:
                ShowInfo(InfoBarSeverity.Warning, "La sesión se cerró", "PowerShell terminó. Reinicia la sesión para seguir.", "Reiniciar", () => App.Controller.RestartShell(_session!));
                break;
            case ShellPhase.Idle when !ShellIntegration.IsPowerShell7(ShellIntegration.FindShell()):
                ShowInfo(InfoBarSeverity.Informational, "Estás usando Windows PowerShell 5.1",
                    "PowerShell 7 es más rápido y entiende más comandos.", "Instalar PowerShell 7",
                    () => App.Controller.Submit("winget install --id Microsoft.PowerShell --source winget", _session!));
                break;
            default:
                ShellInfo.IsOpen = false;
                break;
        }
    }

    private void ShowInfo(InfoBarSeverity severity, string title, string message, string action, Action onAction)
    {
        var button = new Button { Content = action };
        button.Click += (_, _) => onAction();
        ShellInfo.Severity = severity;
        ShellInfo.Title = title;
        ShellInfo.Message = message;
        ShellInfo.ActionButton = button;
        ShellInfo.IsOpen = true;
    }

    private void OnSizeChanged(object sender, SizeChangedEventArgs e) => ApplyChatSize();

    /// <summary>Tells the shell how many columns fit in a bubble, so tables wrap where the bubble does.</summary>
    private void ApplyChatSize()
    {
        if (_shell is null || ActualWidth <= 0) return;
        var bubbleWidth = Math.Min(ActualWidth - 40 - 28, 1200);
        _shell.SetChatSize((int)(bubbleWidth / CellWidth), Math.Max(10, (int)(ActualHeight / CellHeight)));
    }

    // Composer

    private void OnComposerKeyDown(object sender, KeyRoutedEventArgs e)
    {
        var shift = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(CoreVirtualKeyStates.Down);
        var control = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);
        switch (e.Key)
        {
            case VirtualKey.Enter when !shift:
                e.Handled = true;
                Send();
                break;
            // Ctrl+C stops the running program when there's nothing to copy.
            case VirtualKey.C when control && _shell?.IsBusy == true && Composer.SelectionLength == 0:
                e.Handled = true;
                _shell.Interrupt();
                break;
        }
    }

    private void OnSend(object sender, RoutedEventArgs e) => Send();

    private void Send()
    {
        if (_session is null) return;
        var text = Composer.Text.Replace("\r\n", "\n").Replace('\r', '\n');
        // A program waiting for input may want an empty line (“Press Enter”).
        if (text.Trim().Length == 0 && !(_shell?.IsBusy ?? false)) return;
        Composer.Text = "";
        App.Controller.Submit(text, _session);
    }

    private void OnStop(object sender, RoutedEventArgs e)
    {
        if (_session is not null) App.Controller.Stop(_session);
    }

    private void OnExample(object sender, RoutedEventArgs e)
    {
        Composer.Text = (sender as Button)?.Content as string ?? "";
        Composer.SelectionStart = Composer.Text.Length;
        FocusComposer();
    }

    private void OnReveal(object sender, RoutedEventArgs e)
    {
        if (_shell is not null) MainWindow.RevealInExplorer(_shell.Directory);
    }

    private void OnRestart(object sender, RoutedEventArgs e)
    {
        if (_session is not null) App.Controller.RestartShell(_session);
    }
}
