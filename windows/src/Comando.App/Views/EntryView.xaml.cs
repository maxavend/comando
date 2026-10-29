using System.ComponentModel;
using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Shell;
using Comando.Core.Terminal;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.UI;
using Windows.UI.Text;

namespace Comando.Views;

/// <summary>
/// One message pair: the command as the person's bubble, and the output as
/// the answer, live while it runs.
/// </summary>
public sealed partial class EntryView : UserControl
{
    public static readonly DependencyProperty EntryProperty = DependencyProperty.Register(
        nameof(Entry), typeof(CommandEntry), typeof(EntryView),
        new PropertyMetadata(null, (d, e) => ((EntryView)d).Attach(e.OldValue as CommandEntry, e.NewValue as CommandEntry)));

    private ShellSession? _shell;
    private LiveOutput? _live;
    private RenderedOutput _rendered = RenderedOutput.Empty;
    private Comando.Core.Agents.AgentChat? _chat;

    public EntryView()
    {
        InitializeComponent();
    }

    public CommandEntry? Entry
    {
        get => (CommandEntry?)GetValue(EntryProperty);
        set => SetValue(EntryProperty, value);
    }

    private void Attach(CommandEntry? old, CommandEntry? entry)
    {
        if (old is not null) old.PropertyChanged -= OnEntryChanged;
        DetachLive();
        if (entry is null) return;

        entry.PropertyChanged += OnEntryChanged;
        CommandText.Text = entry.Command;
        if (!entry.IsFinished)
        {
            // Only the selected session's chat is on screen.
            _shell = App.Controller.SelectedShell;
            if (_shell is not null) _shell.PropertyChanged += OnShellChanged;
            FollowLive();
        }
        Refresh();
    }

    /// <summary>The list reuses views as it scrolls; one that comes back follows its entry again.</summary>
    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (Entry is not { } entry) return;
        entry.PropertyChanged -= OnEntryChanged;
        Attach(null, entry);
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        if (Entry is { } entry) entry.PropertyChanged -= OnEntryChanged;
        DetachLive();
    }

    private void DetachLive()
    {
        if (_chat is not null) _chat.PropertyChanged -= OnChatChanged;
        _chat = null;
        if (_shell is not null) _shell.PropertyChanged -= OnShellChanged;
        if (_live is not null) _live.PropertyChanged -= OnLiveChanged;
        _shell = null;
        _live = null;
    }

    private void OnEntryChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(CommandEntry.FinishedAt):
                DetachLive();
                Refresh();
                break;
            case nameof(CommandEntry.AgentReply) or nameof(CommandEntry.AssistantReply) or nameof(CommandEntry.AssistantRanAt)
                or nameof(CommandEntry.HintMessage) or nameof(CommandEntry.HintSuggestion) or nameof(CommandEntry.AgentConversationId):
                Refresh();
                break;
        }
    }

    private void OnChatChanged(object? sender, PropertyChangedEventArgs e) => Refresh();

    private void OnShellChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(ShellSession.Live)) FollowLive();
    }

    /// <summary>Watches the shell's running command when it's this entry's.</summary>
    private void FollowLive()
    {
        var live = _shell?.Live is { } current && current.EntryId == Entry?.Id ? current : null;
        if (ReferenceEquals(live, _live)) return;
        if (_live is not null) _live.PropertyChanged -= OnLiveChanged;
        _live = live;
        if (_live is not null) _live.PropertyChanged += OnLiveChanged;
        Refresh();
    }

    private void OnLiveChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(LiveOutput.Version) or nameof(LiveOutput.IsInteractive)) Refresh();
    }

    private void OnThemeChanged(FrameworkElement sender, object args) => Render();

    // Display

    private void Refresh()
    {
        if (Entry is not { } entry) return;
        CommandText.FontSize = Formatting.MessageFontSize;
        OutputText.FontSize = App.Settings.FontSize;
        ExplainItem.Visibility = Formatting.VisibleIf(entry.Kind is EntryKind.Command or EntryKind.Interactive);

        if (entry.Kind is EntryKind.Assistant or EntryKind.Agent or EntryKind.AgentStart)
        {
            ShowReply(entry);
            return;
        }
        ReplyHost.Visibility = Visibility.Collapsed;
        StatusPanel.Visibility = Visibility.Visible;
        if (entry.HintMessage is not null && App.Controller.SelectedSession is { } hinted)
        {
            HintHost.Child = ReplyViews.Hint(entry, hinted);
            HintHost.Visibility = Visibility.Visible;
        }
        else
        {
            HintHost.Child = null;
            HintHost.Visibility = Visibility.Collapsed;
        }

        if (entry.IsFinished)
        {
            CloseTerminal();
            // An interactive program leaves its last screen; anything else, its output.
            _rendered = entry.Transcript is { Length: > 0 } transcript
                ? OutputRenderer.Render(System.Text.Encoding.UTF8.GetBytes(transcript))
                : entry.Output.Length > 0 ? OutputRenderer.Render(entry.Output) : RenderedOutput.Empty;
        }
        else if (_live is { IsInteractive: true })
        {
            OpenTerminal(entry);
            _rendered = RenderedOutput.Empty;
        }
        else if (_live is { } live)
        {
            _rendered = OutputRenderer.RenderTail(live.Buffer, OutputRenderer.LiveLineLimit);
        }
        else
        {
            _rendered = RenderedOutput.Empty;
        }
        Render();
        UpdateStatus(entry);
    }

    /// <summary>The assistant's or an agent's answer instead of terminal output.</summary>
    private void ShowReply(CommandEntry entry)
    {
        OutputBubble.Visibility = Visibility.Collapsed;
        StatusPanel.Visibility = Visibility.Collapsed;
        HintHost.Visibility = Visibility.Collapsed;
        CloseTerminal();
        if (App.Controller.SelectedSession is not { } session) return;
        if (entry.Kind == EntryKind.AgentStart && !entry.IsFinished && _chat is null && App.Controller.AgentChat(session) is { } chat)
        {
            // Its card says when the agent is ready or why it couldn't start.
            _chat = chat;
            _chat.PropertyChanged += OnChatChanged;
        }
        ReplyHost.Child = entry.Kind switch
        {
            EntryKind.Assistant => ReplyViews.Assistant(entry, session),
            EntryKind.AgentStart => ReplyViews.AgentStart(entry, session),
            _ => ReplyViews.AgentTurn(entry, session),
        };
        ReplyHost.Visibility = Visibility.Visible;
    }

    private void Render()
    {
        var running = _live is not null;
        OutputBubble.Visibility = Formatting.VisibleIf(!_rendered.IsEmpty);
        OutputText.Visibility = Formatting.VisibleIf(!_rendered.IsEmpty);
        // Columns that line up with spaces need a monospaced font; sentences read better without.
        OutputText.FontFamily = _rendered.IsTabular
            ? (FontFamily)Application.Current.Resources["TerminalFontFamily"]
            : new FontFamily("Segoe UI Variable Text, Segoe UI");
        Fill(OutputText, _rendered, ActualTheme == ElementTheme.Dark);

        if (!running && _rendered.IsClipped)
        {
            ShowAllButton.Content = $"Mostrar las {_rendered.TotalLines:N0} líneas";
            ShowAllButton.Visibility = Visibility.Visible;
        }
        else
        {
            ShowAllButton.Visibility = Visibility.Collapsed;
        }
    }

    private void OpenTerminal(CommandEntry entry)
    {
        if (TerminalHost.Child is not null || _shell is null) return;
        var card = new TerminalCard();
        card.Attach(_shell, entry.Command);
        TerminalHost.Child = card;
        TerminalHost.Visibility = Visibility.Visible;
        card.Loaded += (_, _) => card.FocusTerminal();
    }

    private void CloseTerminal()
    {
        if (TerminalHost.Child is null) return;
        TerminalHost.Child = null;
        TerminalHost.Visibility = Visibility.Collapsed;
    }

    /// <summary>
    /// Writes styled runs into a RichTextBlock. Backgrounds are highlighters,
    /// because runs can't have one; lines are joined with \n so highlighter
    /// offsets match the text.
    /// </summary>
    internal static void Fill(RichTextBlock block, RenderedOutput rendered, bool dark)
    {
        block.Blocks.Clear();
        block.TextHighlighters.Clear();
        var paragraph = new Paragraph();
        var offset = 0;
        for (var i = 0; i < rendered.Preview.Count; i++)
        {
            if (i > 0)
            {
                paragraph.Inlines.Add(new Run { Text = "\n" });
                offset++;
            }
            foreach (var styled in rendered.Preview[i])
            {
                var run = new Run { Text = styled.Text };
                var style = styled.Style;
                if (!style.IsPlain)
                {
                    var (foreground, background) = OutputRenderer.EffectiveColors(style);
                    Color? textColor = foreground is { } fg ? Formatting.TerminalColor(fg, dark) : null;
                    Color? backColor = background is { } bg ? Formatting.TerminalColor(bg, dark) : null;
                    if (style.Has(StyleFlags.Inverse))
                    {
                        textColor ??= dark ? Color.FromArgb(255, 0x20, 0x20, 0x20) : Colors.White;
                        backColor ??= Formatting.TextColor(dark);
                    }
                    if (style.Has(StyleFlags.Dim))
                    {
                        var baseColor = textColor ?? Formatting.TextColor(dark);
                        textColor = Color.FromArgb((byte)(baseColor.A * 0.6), baseColor.R, baseColor.G, baseColor.B);
                    }
                    if (textColor is { } text) run.Foreground = new SolidColorBrush(text);
                    if (style.Has(StyleFlags.Bold)) run.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
                    if (style.Has(StyleFlags.Italic)) run.FontStyle = FontStyle.Italic;
                    var decorations = TextDecorations.None;
                    if (style.Has(StyleFlags.Underline)) decorations |= TextDecorations.Underline;
                    if (style.Has(StyleFlags.Strikethrough)) decorations |= TextDecorations.Strikethrough;
                    run.TextDecorations = decorations;
                    if (backColor is { } back)
                    {
                        var highlighter = new TextHighlighter { Background = new SolidColorBrush(back) };
                        highlighter.Ranges.Add(new TextRange { StartIndex = offset, Length = styled.Text.Length });
                        block.TextHighlighters.Add(highlighter);
                    }
                }
                paragraph.Inlines.Add(run);
                offset += styled.Text.Length;
            }
        }
        block.Blocks.Add(paragraph);
    }

    private void UpdateStatus(CommandEntry entry)
    {
        var running = !entry.IsFinished;
        RunningRing.IsActive = running;
        RunningRing.Visibility = Formatting.VisibleIf(running);
        StatusIcon.Visibility = Formatting.VisibleIf(!running);
        var failed = false;

        string text;
        if (running)
        {
            text = _live?.IsInteractive == true ? "En curso en la terminal integrada" : "En curso";
        }
        else if (entry.WasInterrupted)
        {
            StatusIcon.Glyph = ""; // Warning
            text = "Se interrumpió: la sesión se cerró mientras corría";
        }
        else if (Formatting.WasStopped(entry.ExitCode))
        {
            StatusIcon.Glyph = ""; // Stop
            text = "Detenido";
        }
        else if (entry.Succeeded)
        {
            StatusIcon.Glyph = ""; // CheckMark
            text = _rendered.IsEmpty ? "Listo, sin nada que mostrar" : "Listo";
        }
        else
        {
            StatusIcon.Glyph = ""; // Error
            StatusIcon.Foreground = (Brush)Application.Current.Resources["SystemFillColorCriticalBrush"];
            text = $"Terminó con error (código {entry.ExitCode})";
        }

        if (!running && entry.Duration is { TotalSeconds: >= 1 } duration)
        {
            text += " · " + Formatting.Duration(duration);
        }
        if (entry.MovedTo is { } folder)
        {
            text += $" · Ahora estás en {FolderName.Phrase(folder)}";
        }
        // The time the message was sent leads, as in a messages app.
        StatusText.Text = entry.StartedAt.ToLocalTime().ToString("HH:mm") + " · " + text;
        VisualStateManager.GoToState(this, failed ? "Failed" : "Normal", false);
    }

    // Actions

    private void OnCopyCommand(object sender, RoutedEventArgs e) => Copy(Entry?.Command);

    /// <summary>Keeps the command in “Mis recetas”, with a title in the person's words.</summary>
    private async void OnSaveRecipe(object sender, RoutedEventArgs e)
    {
        if (Entry is not { } entry) return;
        var title = new TextBox { Header = "Nombre", PlaceholderText = "Por ejemplo: Comprimir las fotos del viaje" };
        var detail = new TextBox { Header = "Qué hace (opcional)" };
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(title);
        panel.Children.Add(detail);
        panel.Children.Add(new TextBlock { Text = entry.Command, FontFamily = (FontFamily)Application.Current.Resources["TerminalFontFamily"], TextWrapping = TextWrapping.Wrap });
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Guardar como receta",
            Content = panel,
            PrimaryButtonText = "Guardar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Primary,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        App.Settings.AddRecipe(new Comando.Core.Services.SavedRecipe
        {
            Title = title.Text.Trim().Length > 0 ? title.Text.Trim() : entry.Command,
            Detail = detail.Text.Trim(),
            Command = entry.Command,
        });
    }

    private void OnExplain(object sender, RoutedEventArgs e)
    {
        if (Entry is { } entry) ReplyViews.ExplainFlyout(entry.Command).ShowAt(CommandBubble);
    }

    private void OnCopyOutput(object sender, RoutedEventArgs e) => Copy(_rendered.PlainText);

    private void OnRunAgain(object sender, RoutedEventArgs e)
    {
        if (Entry is { } entry && App.Controller.SelectedSession is { } session)
        {
            App.Controller.Submit(entry.Command, session);
        }
    }

    private async void OnShowAll(object sender, RoutedEventArgs e)
    {
        if (Entry is not { } entry) return;
        var full = OutputRenderer.Render(OutputRenderer.Buffer(entry.Output, maxLines: int.MaxValue), previewLimit: int.MaxValue);
        var block = new RichTextBlock
        {
            FontFamily = (FontFamily)Application.Current.Resources["TerminalFontFamily"],
            FontSize = 13,
            IsTextSelectionEnabled = true,
            TextWrapping = TextWrapping.NoWrap,
        };
        Fill(block, full, ActualTheme == ElementTheme.Dark);
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = entry.Command,
            Content = new ScrollViewer
            {
                Content = block,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollMode = ScrollMode.Auto,
                MaxHeight = 560,
            },
            PrimaryButtonText = "Copiar todo",
            CloseButtonText = "Cerrar",
            DefaultButton = ContentDialogButton.Close,
        };
        // Wide output needs the room.
        dialog.Resources["ContentDialogMaxWidth"] = 1100.0;
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) Copy(full.PlainText);
    }

    private static void Copy(string? text)
    {
        if (string.IsNullOrEmpty(text)) return;
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContent(package);
    }
}
