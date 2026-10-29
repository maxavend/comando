using Comando.Core.Agents;
using Comando.Core.Assistant;
using Comando.Core.Language;
using Comando.Core.Models;
using Comando.Core.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Comando.Views;

/// <summary>
/// The answers that aren't terminal output: the assistant's replies, an AI
/// agent's turn with its tools, and the card that opens a conversation.
/// Built in code because their parts vary with every answer.
/// </summary>
internal static class ReplyViews
{
    private static TerminalController Controller => App.Controller;

    private static Brush Resource(string key) => (Brush)Application.Current.Resources[key];

    private static Style TextStyle(string key) => (Style)Application.Current.Resources[key];

    private static FontFamily Mono => (FontFamily)Application.Current.Resources["TerminalFontFamily"];

    public static Border Bubble(UIElement content) => new()
    {
        Style = (Style)Application.Current.Resources["OutputBubbleStyle"],
        Child = content,
        MaxWidth = 760,
    };

    private static TextBlock Paragraph(string text, bool secondary = false)
    {
        var block = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        // Only set when it differs: a null brush would make the text invisible.
        if (secondary) block.Foreground = Resource("TextFillColorSecondaryBrush");
        return block;
    }

    private static FontIcon Icon(string glyph, double size = 14) => new() { Glyph = glyph, FontSize = size };

    // Assistant

    public static UIElement Assistant(CommandEntry entry, TerminalSession session)
    {
        var reply = entry.AssistantReply ?? new AssistantReply();
        var stack = new StackPanel { Spacing = 10 };

        if (reply.IsWriting && reply.Explanation is null && reply.Proposals.Count == 0)
        {
            var thinking = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            thinking.Children.Add(new ProgressRing { IsActive = true, Width = 14, Height = 14 });
            thinking.Children.Add(Paragraph("Pensando…", secondary: true));
            stack.Children.Add(thinking);
            return Bubble(stack);
        }

        if (reply.Error is { } error)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            row.Children.Add(Icon(""));
            row.Children.Add(Paragraph(error));
            stack.Children.Add(row);
        }
        if (reply.Explanation is { Length: > 0 } explanation) stack.Children.Add(Paragraph(explanation));

        foreach (var point in reply.Points)
        {
            var grid = new Grid { ColumnSpacing = 12 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var icon = Icon(point.Glyph, 16);
            icon.VerticalAlignment = VerticalAlignment.Top;
            icon.Margin = new Thickness(0, 2, 0, 0);
            grid.Children.Add(icon);
            var text = new StackPanel();
            text.Children.Add(new TextBlock { Text = point.Title, Style = TextStyle("BodyStrongTextBlockStyle"), TextWrapping = TextWrapping.Wrap });
            text.Children.Add(Paragraph(point.Detail, secondary: true));
            Grid.SetColumn(text, 1);
            grid.Children.Add(text);
            stack.Children.Add(grid);
        }

        foreach (var proposal in reply.Proposals)
        {
            stack.Children.Add(CommandCard(proposal.Command, proposal.Explanation));
        }
        if (reply.Proposals.Count > 0 && !reply.IsWriting)
        {
            var ran = entry.AssistantRanAt is not null;
            var run = new Button
            {
                Content = ran ? "Ejecutado" : reply.Proposals.Count > 1 ? "Ejecutar todo" : "Ejecutar",
                Style = ran ? null : (Style)Application.Current.Resources["AccentButtonStyle"],
                IsEnabled = !ran,
            };
            run.Click += (_, _) => Controller.RunProposals(entry, session);
            var edit = new Button { Content = "Editar antes" };
            edit.Click += (_, _) => App.Window?.Chat.Draft(string.Join("; ", reply.Proposals.Select(p => p.Command)));
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            buttons.Children.Add(run);
            buttons.Children.Add(edit);
            stack.Children.Add(buttons);
        }

        if (reply.ToolsToInstall.Count > 0 && !reply.IsWriting)
        {
            stack.Children.Add(Paragraph("Para esto hace falta una herramienta que no tienes:", secondary: true));
            foreach (var tool in reply.ToolsToInstall)
            {
                var row = new Grid { ColumnSpacing = 12 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.Children.Add(Paragraph(tool.Explanation));
                var install = new Button { Content = "Instalar", VerticalAlignment = VerticalAlignment.Center };
                install.Click += (_, _) => Controller.RunInstall(tool.Command, session);
                Grid.SetColumn(install, 1);
                row.Children.Add(install);
                stack.Children.Add(row);
            }
        }

        if (reply.IsWriting)
        {
            stack.Children.Add(new ProgressBar { IsIndeterminate = true, MaxWidth = 120, HorizontalAlignment = HorizontalAlignment.Left });
        }
        return Bubble(stack);
    }

    /// <summary>A proposed command with what it does, and what each part means on demand.</summary>
    public static UIElement CommandCard(string command, string explanation)
    {
        var card = new StackPanel { Spacing = 4 };
        var code = new Border
        {
            Background = Resource("SubtleFillColorSecondaryBrush"),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10, 8, 10, 8),
            Child = new TextBlock { Text = command, FontFamily = Mono, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true },
        };
        var risk = DangerDetector.Risk(command);
        card.Children.Add(code);
        if (explanation.Length > 0) card.Children.Add(Paragraph(explanation, secondary: true));
        if (risk is not null)
        {
            var warning = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            warning.Children.Add(new FontIcon { Glyph = "", FontSize = 12, Foreground = Resource("SystemFillColorCautionBrush") });
            warning.Children.Add(new TextBlock { Text = risk.Title, Style = TextStyle("CaptionTextBlockStyle"), TextWrapping = TextWrapping.Wrap });
            card.Children.Add(warning);
        }
        code.ContextFlyout = ExplainFlyout(command);
        return card;
    }

    /// <summary>“Qué hace cada parte”: every word of a command, explained.</summary>
    public static Flyout ExplainFlyout(string command)
    {
        var list = new StackPanel { Spacing = 8, MaxWidth = 420 };
        list.Children.Add(new TextBlock { Text = "Qué hace cada parte", Style = TextStyle("BodyStrongTextBlockStyle") });
        foreach (var part in CommandExplainer.Parts(command))
        {
            var row = new StackPanel();
            row.Children.Add(new TextBlock { Text = part.Token, FontFamily = Mono, TextWrapping = TextWrapping.Wrap });
            row.Children.Add(Paragraph(part.Explanation, secondary: true));
            list.Children.Add(row);
        }
        return new Flyout { Content = new ScrollViewer { Content = list, MaxHeight = 420 } };
    }

    // Agents

    public static UIElement AgentStart(CommandEntry entry, TerminalSession session)
    {
        var kind = entry.AgentKind ?? AgentKind.Claude;
        var chat = entry.IsFinished ? null : Controller.AgentChat(session);
        var stack = new StackPanel { Spacing = 8 };
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        title.Children.Add(Icon("", 18));
        title.Children.Add(new TextBlock { Text = $"Conversación con {kind.DisplayName()}", Style = TextStyle("BodyStrongTextBlockStyle"), VerticalAlignment = VerticalAlignment.Center });
        stack.Children.Add(title);

        string status;
        if (entry.IsFinished) status = "La conversación terminó.";
        else if (chat?.StartupError is { } startupError) status = startupError;
        else if (chat is { IsReady: true }) status = "Escribe abajo: cada mensaje le llega y su respuesta aparece aquí.";
        else status = $"Abriendo {kind.CommandName()}…";
        stack.Children.Add(Paragraph(status, secondary: true));

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (!entry.IsFinished)
        {
            var screen = new Button { Content = "Abrir su pantalla" };
            screen.Click += (_, _) => Controller.OpenAgentInTerminal(session);
            var end = new Button { Content = "Terminar" };
            end.Click += (_, _) => Controller.EndAgent(session);
            buttons.Children.Add(screen);
            buttons.Children.Add(end);
        }
        else if (entry.AgentConversationId is not null && Controller.AgentChat(session) is null)
        {
            var resume = new Button { Content = "Retomar la conversación" };
            resume.Click += (_, _) => Controller.ResumeAgent(entry, session);
            buttons.Children.Add(resume);
        }
        if (buttons.Children.Count > 0) stack.Children.Add(buttons);
        return Bubble(stack);
    }

    public static UIElement AgentTurn(CommandEntry entry, TerminalSession session)
    {
        var reply = entry.AgentReply ?? new AgentReply();
        var kind = entry.AgentKind ?? AgentKind.Claude;
        var stack = new StackPanel { Spacing = 8 };

        foreach (var step in reply.Steps)
        {
            stack.Children.Add(step.Kind == AgentStepKind.Text ? Bubble(Paragraph(step.Text)) : ToolCard(step));
        }

        if (!entry.IsFinished)
        {
            var working = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(4, 0, 0, 0) };
            working.Children.Add(new ProgressRing { IsActive = true, Width = 14, Height = 14 });
            working.Children.Add(new TextBlock { Text = $"{kind.DisplayName()} está trabajando", Style = TextStyle("CaptionTextBlockStyle"), Foreground = Resource("TextFillColorSecondaryBrush"), VerticalAlignment = VerticalAlignment.Center });
            var stop = new HyperlinkButton { Content = "Detener", Padding = new Thickness(4, 0, 4, 0) };
            stop.Click += (_, _) => Controller.StopAgent(session);
            working.Children.Add(stop);
            stack.Children.Add(working);
        }

        if (reply.Denied.Count > 0 && entry.IsFinished)
        {
            var denied = new StackPanel { Spacing = 8 };
            var actions = string.Join(", ", reply.Denied.Select(DeniedAction.Describe).Distinct());
            denied.Children.Add(Paragraph($"{kind.DisplayName()} quiso {actions}, pero necesita tu permiso."));
            if (kind.HasPermissionModes())
            {
                var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                var edits = new Button { Content = "Permitir crear y editar archivos", Style = (Style)Application.Current.Resources["AccentButtonStyle"] };
                edits.Click += (_, _) => Controller.AllowAgent(AgentPermission.Edits, session);
                var all = new Button { Content = "Permitir todo" };
                all.Click += (_, _) => Controller.AllowAgent(AgentPermission.All, session);
                buttons.Children.Add(edits);
                buttons.Children.Add(all);
                denied.Children.Add(buttons);
            }
            else
            {
                var screen = new Button { Content = "Abrir su pantalla para darle permiso" };
                screen.Click += (_, _) => Controller.OpenAgentInTerminal(session);
                denied.Children.Add(screen);
            }
            stack.Children.Add(Bubble(denied));
        }

        if (reply.Error is { } error)
        {
            var row = new StackPanel { Spacing = 6 };
            row.Children.Add(Paragraph(error));
            if (reply.OpenedTerminal == true) row.Children.Add(Paragraph("Abrí su pantalla aquí abajo para que lo resuelvas. Al cerrarla, la conversación sigue en el chat.", secondary: true));
            stack.Children.Add(Bubble(row));
        }
        return stack;
    }

    private static UIElement ToolCard(AgentStep step)
    {
        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (step.State == AgentStepState.Running)
        {
            header.Children.Add(new ProgressRing { IsActive = true, Width = 14, Height = 14 });
        }
        else
        {
            var icon = new FontIcon { Glyph = step.State == AgentStepState.Failed ? "\uE783" : step.Glyph ?? "\uE90F", FontSize = 14 };
            if (step.State == AgentStepState.Failed) icon.Foreground = Resource("SystemFillColorCriticalBrush");
            header.Children.Add(icon);
        }
        header.Children.Add(new TextBlock
        {
            Text = step.State == AgentStepState.Failed && step.FailedText is not null ? step.FailedText : step.Text,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
        });

        var body = new StackPanel { Spacing = 6 };
        if (step.Detail is { Length: > 0 } detail)
        {
            body.Children.Add(new TextBlock { Text = detail, FontFamily = Mono, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        }
        if (step.Output is { Length: > 0 } output)
        {
            body.Children.Add(new ScrollViewer
            {
                MaxHeight = 240,
                Content = new TextBlock { Text = output, FontFamily = Mono, FontSize = 12, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, Foreground = Resource("TextFillColorSecondaryBrush") },
            });
        }
        if (body.Children.Count == 0)
        {
            return new Border
            {
                Padding = new Thickness(12, 8, 12, 8),
                CornerRadius = new CornerRadius(8),
                Background = Resource("CardBackgroundFillColorSecondaryBrush"),
                Child = header,
                HorizontalAlignment = HorizontalAlignment.Left,
            };
        }
        return new Expander
        {
            Header = header,
            Content = body,
            HorizontalAlignment = HorizontalAlignment.Left,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            MaxWidth = 760,
            MinWidth = 320,
        };
    }

    // Hints

    /// <summary>Why a command failed, in plain words, with a command to try instead.</summary>
    public static UIElement Hint(CommandEntry entry, TerminalSession session)
    {
        var stack = new StackPanel { Spacing = 8 };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(new FontIcon { Glyph = "", FontSize = 14, Foreground = Resource("SystemFillColorCautionBrush") });
        row.Children.Add(new TextBlock { Text = entry.HintMessage, TextWrapping = TextWrapping.Wrap, MaxWidth = 640 });
        stack.Children.Add(row);
        if (entry.HintSuggestion is { } suggestion)
        {
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var run = new Button { Content = $"Probar {suggestion}" };
            run.Click += (_, _) => Controller.Submit(suggestion, session);
            var edit = new Button { Content = "Editar" };
            edit.Click += (_, _) => App.Window?.Chat.Draft(suggestion);
            buttons.Children.Add(run);
            buttons.Children.Add(edit);
            stack.Children.Add(buttons);
        }
        return new Border
        {
            Background = Resource("CardBackgroundFillColorDefaultBrush"),
            BorderBrush = Resource("CardStrokeColorDefaultBrush"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(14, 10, 14, 10),
            Child = stack,
            MaxWidth = 760,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
    }
}
