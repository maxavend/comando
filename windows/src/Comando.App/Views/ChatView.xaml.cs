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
    private Comando.Core.Agents.AgentChat? _chat;
    private readonly List<string> _attachments = [];

    public ChatView()
    {
        InitializeComponent();
        App.Controller.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(Comando.Core.Services.TerminalController.AgentChatsVersion)) UpdateShellState();
            if (e.PropertyName == nameof(Comando.Core.Services.TerminalController.AssistantRequestsInFlight)) UpdateThinking();
        };
        App.Settings.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(Comando.Core.Services.AppSettings.FontSize)) Composer.FontSize = Formatting.MessageFontSize;
        };
        Composer.FontSize = Formatting.MessageFontSize;
    }

    private bool _thinking;

    /// <summary>While the assistant thinks, the field shows Fluent's progress bar.</summary>
    private void UpdateThinking()
    {
        var thinking = App.Controller.AssistantRequestsInFlight > 0;
        if (thinking == _thinking) return;
        _thinking = thinking;
        UpdateShellState();
    }

    /// <summary>Places a command in the composer to edit before sending.</summary>
    public void Draft(string text)
    {
        Composer.Text = text;
        Composer.SelectionStart = text.Length;
        FocusComposer();
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
            _attachments.Clear();
            UpdateAttachments();
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
        if (e.PropertyName is nameof(TerminalSession.DisplayName) or nameof(TerminalSession.Directory)
            or nameof(TerminalSession.Emoji) or nameof(TerminalSession.ColorIndex)) UpdateHeader();
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
        if (_session is not null)
        {
            AvatarFill.Fill = Formatting.SessionBrush(_session.ColorIndex);
            AvatarEmoji.Text = _session.Emoji ?? "";
            AvatarGlyph.Glyph = Formatting.SessionGlyph(_shell?.Directory ?? _session.Directory);
            AvatarGlyph.Visibility = Formatting.GlyphVisibility(_session.Emoji);
        }
        FolderText.Text = _shell?.Directory ?? _session?.Directory ?? "";
    }

    private void UpdateEmptyState()
    {
        EmptyState.Visibility = Formatting.VisibleIf(_session is { Entries.Count: 0 });
    }

    private void OnChatChanged(object? sender, PropertyChangedEventArgs e) => UpdateShellState();

    private void UpdateShellState()
    {
        var chat = _session is null ? null : App.Controller.AgentChat(_session);
        if (!ReferenceEquals(chat, _chat))
        {
            if (_chat is not null) _chat.PropertyChanged -= OnChatChanged;
            _chat = chat;
            if (_chat is not null) _chat.PropertyChanged += OnChatChanged;
        }
        var busy = _shell?.IsBusy ?? false;
        var agentWorking = !busy && chat is { IsResponding: true };
        // Stop takes Send's place inside the field while something runs.
        var running = busy || agentWorking;
        StopButton.Visibility = Formatting.VisibleIf(running);
        SendButton.Visibility = Formatting.VisibleIf(!running);
        ActivityBar.Visibility = Formatting.VisibleIf(running || _thinking);
        Composer.PlaceholderText = busy ? "Escribe para responderle al programa"
            : _thinking ? "El asistente está pensando…"
            : chat is not null ? $"Escribe a {Comando.Core.Agents.AgentKinds.DisplayName(chat.Kind)}"
            : _attachments.Count > 0 ? "Dile al asistente qué hacer con estos archivos"
            : App.Settings.AssistantEnabled ? "Escribe un comando o pídelo con tus palabras"
            : "Escribe un comando";

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
            case VirtualKey.Tab when !shift && !control && !(_shell?.IsBusy ?? false):
                e.Handled = true;
                Complete();
                break;
            // Up in an empty field brings back the last command, like a terminal.
            case VirtualKey.Up when Composer.Text.Length == 0 && _session is not null:
                if (_session.Entries.LastOrDefault(entry => entry.Kind == EntryKind.Command) is { } last)
                {
                    e.Handled = true;
                    Draft(last.Command);
                }
                break;
            // Ctrl+C stops the running program when there's nothing to copy.
            case VirtualKey.C when control && _shell?.IsBusy == true && Composer.SelectionLength == 0:
                e.Handled = true;
                _shell.Interrupt();
                break;
        }
    }

    private void OnSend(object sender, RoutedEventArgs e) => Send();

    /// <summary>The send button lights up once there's something to send.</summary>
    private void OnComposerTextChanged(object sender, TextChangedEventArgs e) => UpdateSendButton();

    private void UpdateSendButton()
    {
        SendButton.IsEnabled = Composer.Text.Trim().Length > 0 || _attachments.Count > 0;
        // Its icon keeps the accent color, so it dims by hand while there's nothing to send.
        SendButton.Opacity = SendButton.IsEnabled ? 1 : 0.4;
    }

    /// <summary>
    /// Tab completes the word before the cursor: a program for the first
    /// word, otherwise a file or folder. Several matches are offered in a menu.
    /// </summary>
    private void Complete()
    {
        if (_shell is null) return;
        var text = Composer.Text[..Composer.SelectionStart];
        var start = text.LastIndexOfAny([' ', '\t', '"', '\'']) + 1;
        var word = text[start..];
        var isFirst = text[..start].Trim().Length == 0;
        var matches = Completions(word, isFirst).Take(40).ToList();
        if (matches.Count == 0) return;
        if (matches.Count == 1)
        {
            Insert(start, word, matches[0]);
            return;
        }
        var common = matches.Aggregate((a, b) => CommonPrefix(a, b));
        if (common.Length > word.Length)
        {
            Insert(start, word, common, finished: false);
            return;
        }
        var menu = new MenuFlyout();
        foreach (var match in matches)
        {
            var item = new MenuFlyoutItem { Text = match };
            item.Click += (_, _) => Insert(start, word, match);
            menu.Items.Add(item);
        }
        menu.ShowAt(Composer);
    }

    private IEnumerable<string> Completions(string word, bool isFirst)
    {
        var results = new List<string>();
        if (isFirst && !word.Contains('\\') && !word.Contains('/'))
        {
            results.AddRange(ExecutableIndex.Names(_shell!.PathEntries)
                .Where(name => name.StartsWith(word, StringComparison.OrdinalIgnoreCase))
                .OrderBy(name => name.Length));
        }
        try
        {
            var separator = word.LastIndexOfAny(['\\', '/']);
            var folderPart = separator >= 0 ? word[..(separator + 1)] : "";
            var prefix = word[(separator + 1)..];
            var folder = Path.GetFullPath(Path.Combine(_shell!.Directory, folderPart.Length > 0 ? folderPart : "."));
            foreach (var entry in Directory.EnumerateFileSystemEntries(folder, prefix + "*").Take(200))
            {
                var name = Path.GetFileName(entry);
                results.Add(folderPart + name + (Directory.Exists(entry) ? "\\" : ""));
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
        }
        return results.Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private void Insert(int start, string word, string completion, bool finished = true)
    {
        // Names with spaces need quotes in PowerShell.
        var value = completion.Contains(' ') ? $"'{completion}'" : completion;
        if (finished && !completion.EndsWith('\\')) value += " ";
        var before = Composer.Text[..start];
        var after = Composer.Text[(start + word.Length)..];
        Composer.Text = before + value + after;
        Composer.SelectionStart = before.Length + value.Length;
    }

    private static string CommonPrefix(string a, string b)
    {
        var length = 0;
        while (length < a.Length && length < b.Length && char.ToLowerInvariant(a[length]) == char.ToLowerInvariant(b[length])) length++;
        return a[..length];
    }

    private void Send()
    {
        if (_session is null) return;
        var text = Composer.Text.Replace("\r\n", "\n").Replace('\r', '\n');
        // A program waiting for input may want an empty line (“Press Enter”).
        if (text.Trim().Length == 0 && !(_shell?.IsBusy ?? false)) return;
        Composer.Text = "";
        var attachments = _attachments.ToList();
        _attachments.Clear();
        UpdateAttachments();
        App.Controller.Send(text, _session, attachments);
    }

    private void OnStop(object sender, RoutedEventArgs e)
    {
        if (_session is null) return;
        if (_shell?.IsBusy == true) App.Controller.Stop(_session);
        else App.Controller.StopAgent(_session);
    }

    // Files and folders

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems)) return;
        e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Link;
        e.DragUIOverride.Caption = "Soltar para adjuntar, o una carpeta para ir a ella";
    }

    /// <summary>A folder on its own moves the session there; files are attached for the assistant.</summary>
    private async void OnDrop(object sender, DragEventArgs e)
    {
        if (_session is null || !e.DataView.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems)) return;
        var items = await e.DataView.GetStorageItemsAsync();
        if (items.Count == 1 && items[0] is Windows.Storage.StorageFolder folder)
        {
            App.Controller.GoTo(folder.Path, _session);
            return;
        }
        foreach (var item in items)
        {
            if (!_attachments.Contains(item.Path)) _attachments.Add(item.Path);
        }
        UpdateAttachments();
        FocusComposer();
    }

    private void UpdateAttachments()
    {
        AttachmentBar.Children.Clear();
        foreach (var path in _attachments)
        {
            var chip = new Button { Content = $"{Path.GetFileName(path)}  ✕", CornerRadius = new CornerRadius(12), Padding = new Thickness(10, 3, 10, 3) };
            ToolTipService.SetToolTip(chip, $"Quitar {path}");
            chip.Click += (_, _) =>
            {
                _attachments.Remove(path);
                UpdateAttachments();
            };
            AttachmentBar.Children.Add(chip);
        }
        AttachmentBar.Visibility = Formatting.VisibleIf(_attachments.Count > 0);
        UpdateSendButton();
        UpdateShellState();
    }

    private async void OnChangeFolder(object sender, RoutedEventArgs e)
    {
        if (_session is null || App.Window is null) return;
        var picker = new Windows.Storage.Pickers.FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(App.Window));
        if (await picker.PickSingleFolderAsync() is { } folder) App.Controller.GoTo(folder.Path, _session);
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
