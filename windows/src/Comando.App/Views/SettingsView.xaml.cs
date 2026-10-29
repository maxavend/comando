using Comando.Core.Assistant;
using Comando.Core.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace Comando.Views;

/// <summary>Preferences, each saved as soon as it changes.</summary>
public sealed partial class SettingsView : UserControl
{
    // True until Show fills the controls: building them fires their change
    // events (the slider snaps to its minimum), which mustn't save anything.
    private bool _loading = true;

    public SettingsView()
    {
        InitializeComponent();
    }

    public event Action? BackRequested;
    public event Action? WelcomeRequested;

    private static AppSettings Settings => App.Settings;

    public void Show()
    {
        _loading = true;
        ThemeBox.SelectedIndex = (int)Settings.Theme;
        FontSizeSlider.Value = Settings.FontSize;
        FontPreview.FontSize = Settings.FontSize;
        NotifyBox.SelectedItem = NotifyBox.Items.OfType<ComboBoxItem>()
            .FirstOrDefault(item => (string)item.Tag == ((int)Settings.NotifyAfterSeconds).ToString()) ?? NotifyBox.Items[1];
        AssistantSwitch.IsOn = Settings.AssistantEnabled;
        OnlineSwitch.IsOn = Settings.SearchesToolsOnline;
        ConfirmSwitch.IsOn = Settings.ConfirmRiskyCommands;
        AgentsSwitch.IsOn = Settings.AgentsAsChat;
        InteractiveBox.Text = Settings.InteractiveCommandsText;
        VersionText.Text = $"Comando {App.Version} para Windows";
        _loading = false;
        UpdateModelStatus();
    }

    private void UpdateModelStatus()
    {
        var availability = App.Model.Availability;
        ModelStatus.Text = availability switch
        {
            ModelAvailability.Ready => "Phi Silica está listo.",
            ModelAvailability.NeedsSetup => "Windows tiene que preparar Phi Silica antes del primer uso.",
            ModelAvailability.DisabledByUser => "Los modelos de IA están desactivados en la configuración de Windows. La guía y las recetas siguen funcionando.",
            _ => "Este PC no tiene Phi Silica (necesita un PC Copilot+ y Comando instalado como paquete). La guía, las recetas y los comandos siguen funcionando.",
        };
        PrepareModelButton.Visibility = Formatting.VisibleIf(availability == ModelAvailability.NeedsSetup);
    }

    private async void OnPrepareModel(object sender, RoutedEventArgs e)
    {
        PrepareModelButton.IsEnabled = false;
        ModelStatus.Text = "Preparando Phi Silica… puede tardar unos minutos.";
        await App.Model.PrepareAsync();
        PrepareModelButton.IsEnabled = true;
        UpdateModelStatus();
    }

    private void OnBack(object sender, RoutedEventArgs e) => BackRequested?.Invoke();

    private void OnShowWelcome(object sender, RoutedEventArgs e) => WelcomeRequested?.Invoke();

    private void OnThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loading && ThemeBox.SelectedIndex >= 0) Settings.Theme = (AppTheme)ThemeBox.SelectedIndex;
    }

    private void OnFontSizeChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (FontPreview is null) return;
        FontPreview.FontSize = e.NewValue;
        if (!_loading) Settings.FontSize = e.NewValue;
    }

    private void OnNotifyChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_loading && NotifyBox.SelectedItem is ComboBoxItem { Tag: string seconds }) Settings.NotifyAfterSeconds = double.Parse(seconds);
    }

    private void OnAssistantToggled(object sender, RoutedEventArgs e)
    {
        if (!_loading) Settings.AssistantEnabled = AssistantSwitch.IsOn;
    }

    private void OnOnlineToggled(object sender, RoutedEventArgs e)
    {
        if (!_loading) Settings.SearchesToolsOnline = OnlineSwitch.IsOn;
    }

    private void OnConfirmToggled(object sender, RoutedEventArgs e)
    {
        if (!_loading) Settings.ConfirmRiskyCommands = ConfirmSwitch.IsOn;
    }

    private void OnAgentsToggled(object sender, RoutedEventArgs e)
    {
        if (!_loading) Settings.AgentsAsChat = AgentsSwitch.IsOn;
    }

    private void OnInteractiveChanged(object sender, RoutedEventArgs e)
    {
        var text = InteractiveBox.Text.Trim();
        Settings.InteractiveCommandsText = text.Length == 0 ? AppSettings.DefaultInteractiveCommands : text;
    }
}
