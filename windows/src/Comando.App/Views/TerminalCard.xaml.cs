using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Comando.Core.Shell;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;

namespace Comando.Views;

/// <summary>
/// A real terminal inside the chat, for programs that draw their own screen
/// (vim, ssh, REPLs, AI agents): xterm.js in a WebView2, fed by the shell's
/// pseudoconsole.
/// </summary>
public sealed partial class TerminalCard : UserControl
{
    private const string Host = "comando.terminal";
    private ShellSession? _shell;
    private bool _ready;
    private readonly List<byte[]> _pending = [];
    private string? _transcript;

    public TerminalCard()
    {
        InitializeComponent();
    }

    /// <summary>Connects the card to the shell whose program it shows.</summary>
    public void Attach(ShellSession shell, string command)
    {
        _shell = shell;
        TitleText.Text = command;
        shell.TranscriptProvider = () => _transcript;
        shell.AttachInteractiveSink(Write);
    }

    public void FocusTerminal()
    {
        View.Focus(FocusState.Programmatic);
        Post(new JsonObject { ["type"] = "focus" });
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            await View.EnsureCoreWebView2Async();
        }
        catch (Exception)
        {
            // Without the WebView2 runtime the program still runs; the chat says so.
            TitleText.Text = "No se pudo abrir la terminal integrada (falta WebView2)";
            return;
        }
        var core = View.CoreWebView2;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;
        core.SetVirtualHostNameToFolderMapping(Host, Path.Combine(AppContext.BaseDirectory, "Assets", "Terminal"),
            CoreWebView2HostResourceAccessKind.Allow);
        core.WebMessageReceived += OnMessage;
        core.Navigate($"https://{Host}/terminal.html");
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        _shell?.DetachInteractiveSink();
        if (View.CoreWebView2 is { } core) core.WebMessageReceived -= OnMessage;
    }

    private void OnThemeChanged(FrameworkElement sender, object args) => SendTheme();

    private void OnStop(object sender, RoutedEventArgs e)
    {
        if (_shell is not null) _ = _shell.QuitForegroundAsync();
    }

    private void OnMessage(CoreWebView2 sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        JsonNode? message;
        try
        {
            message = JsonNode.Parse(args.WebMessageAsJson);
        }
        catch (JsonException)
        {
            return;
        }
        switch ((string?)message?["type"])
        {
            case "ready":
                _ready = true;
                SendTheme();
                Resize(message);
                foreach (var bytes in _pending) Write(bytes);
                _pending.Clear();
                break;
            case "resize":
                Resize(message);
                break;
            case "input":
                if ((string?)message?["data"] is { } data) _shell?.SendRaw(Encoding.UTF8.GetBytes(data));
                break;
            case "transcript":
                _transcript = (string?)message?["text"];
                break;
        }
    }

    private void Resize(JsonNode? message)
    {
        if (message?["cols"] is JsonNode cols && message["rows"] is JsonNode rows)
        {
            _shell?.ApplyWindowSize((int)cols, (int)rows);
        }
    }

    private void Write(byte[] bytes)
    {
        if (!_ready)
        {
            _pending.Add(bytes);
            return;
        }
        Post(new JsonObject { ["type"] = "write", ["data"] = Convert.ToBase64String(bytes) });
    }

    private void SendTheme()
    {
        if (!_ready) return;
        var dark = ActualTheme == ElementTheme.Dark;
        var theme = new JsonObject
        {
            ["background"] = dark ? "#202020" : "#FFFFFF",
            ["foreground"] = dark ? "#E6E6E6" : "#1F1F1F",
            ["cursor"] = dark ? "#E6E6E6" : "#1F1F1F",
            ["selectionBackground"] = dark ? "#264F78" : "#ADD6FF",
            ["black"] = dark ? "#3C3C3C" : "#1F1F1F",
            ["red"] = dark ? "#FF6B63" : "#C41A16",
            ["green"] = dark ? "#5FD37A" : "#1F8A3B",
            ["yellow"] = dark ? "#F2C84B" : "#9A6B00",
            ["blue"] = dark ? "#6AA9FF" : "#0B5FD6",
            ["magenta"] = dark ? "#E08BF0" : "#A22EB8",
            ["cyan"] = dark ? "#5CD6E0" : "#0E7C86",
            ["white"] = dark ? "#C8C8C8" : "#6E6E6E",
            ["brightBlack"] = dark ? "#8A8A8A" : "#8A8A8A",
            ["brightRed"] = dark ? "#FF8A80" : "#E02F28",
            ["brightGreen"] = dark ? "#8CEEA0" : "#2BA34C",
            ["brightYellow"] = dark ? "#FFDE7A" : "#B38000",
            ["brightBlue"] = dark ? "#9AC5FF" : "#2F7BF0",
            ["brightMagenta"] = dark ? "#F0B0FA" : "#BF4FD4",
            ["brightCyan"] = dark ? "#8DECF2" : "#1296A1",
            ["brightWhite"] = dark ? "#FFFFFF" : "#1F1F1F",
        };
        Post(new JsonObject { ["type"] = "theme", ["theme"] = theme });
    }

    private void Post(JsonObject message)
    {
        if (_ready && View.CoreWebView2 is { } core) core.PostWebMessageAsJson(message.ToJsonString());
    }
}
