using System.ComponentModel;
using Comando.Core.Assistant;
using Comando.Core.Tools;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Comando.Views;

/// <summary>
/// What's installed with winget, Scoop, npm, pipx and uv, what can be
/// updated, and tools worth having. Every change runs as a visible command
/// in a session, so its output stays in the chat.
/// </summary>
public sealed partial class ToolsView : UserControl
{
    private PackageStore? _store;

    public ToolsView()
    {
        InitializeComponent();
    }

    /// <summary>Asks to go back to the chat.</summary>
    public event Action? BackRequested;

    public void Show()
    {
        if (_store is null)
        {
            _store = new PackageStore(App.Dispatcher, () => App.Controller.SelectedShell?.PathEntries ?? []);
            _store.PropertyChanged += OnStoreChanged;
        }
        _ = _store.Refresh();
        Update();
    }

    public static string VersionText(string origin, string version, string? latest) =>
        string.IsNullOrEmpty(latest) || latest == version
            ? $"{origin} · {version}"
            : $"{origin} · {version} → {latest}";

    private void OnStoreChanged(object? sender, PropertyChangedEventArgs e) => Update();

    private void Update()
    {
        if (_store is null) return;
        LoadingRing.IsActive = _store.IsLoading || _store.IsCheckingUpdates;
        var outdated = _store.OutdatedCount;
        OutdatedTab.Text = outdated > 0 ? $"Por actualizar ({outdated})" : "Por actualizar";
        SummaryText.Text = _store.HasLoaded
            ? $"{_store.Packages.Count} instaladas · {(outdated == 0 ? "todo al día" : outdated == 1 ? "1 por actualizar" : $"{outdated} por actualizar")}"
            : "Revisando lo que tienes instalado…";
        UpgradeAllButton.Visibility = Formatting.VisibleIf(Tabs.SelectedItem == OutdatedTab && outdated > 0);

        var query = TextNormalizer.Normalize(FilterBox.Text);
        bool Matches(string text) => query.Length == 0 || TextNormalizer.Normalize(text).Contains(query);

        if (Tabs.SelectedItem == DiscoverTab)
        {
            var tools = ToolCatalog.Search(FilterBox.Text);
            CatalogList.ItemsSource = tools;
            CatalogList.Visibility = Visibility.Visible;
            PackageList.Visibility = Visibility.Collapsed;
            ShowEmpty(tools.Count == 0 ? "No hay herramientas con ese nombre." : null);
            return;
        }

        var packages = _store.Packages
            .Where(p => Tabs.SelectedItem != OutdatedTab || p.IsOutdated)
            .Where(p => Matches(p.Name) || Matches(p.Id))
            .OrderBy(p => p.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
        PackageList.ItemsSource = packages;
        PackageList.Visibility = Visibility.Visible;
        CatalogList.Visibility = Visibility.Collapsed;
        string? empty = null;
        if (packages.Count == 0 && _store.HasLoaded)
        {
            empty = Tabs.SelectedItem == OutdatedTab ? "Todo está al día."
                : _store.AvailableManagers.Count == 0 ? "No encontré winget, Scoop, npm, pipx ni uv en este PC."
                : "No hay nada con ese nombre.";
        }
        ShowEmpty(empty ?? (packages.Count == 0 ? _store.LastError : null));
    }

    private void ShowEmpty(string? text)
    {
        EmptyText.Text = text ?? "";
        EmptyText.Visibility = Formatting.VisibleIf(!string.IsNullOrEmpty(text));
    }

    private void OnTabChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args) => Update();

    private void OnFilterChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) => Update();

    private void OnRefresh(object sender, RoutedEventArgs e) => _ = _store?.Refresh();

    private void OnBack(object sender, RoutedEventArgs e) => BackRequested?.Invoke();

    private void OnUpgrade(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is InstalledPackage package) Run(package.UpgradeCommand);
    }

    private void OnUpgradeAll(object sender, RoutedEventArgs e)
    {
        if (_store is null) return;
        var commands = _store.Packages.Where(p => p.IsOutdated).Select(p => p.Manager).Distinct().Select(m => m.UpgradeAllCommand());
        Run(string.Join("; ", commands));
    }

    private async void OnUninstall(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not InstalledPackage package) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"¿Desinstalar {package.Name}?",
            Content = $"Se ejecuta en el chat: {package.UninstallCommand}",
            PrimaryButtonText = "Desinstalar",
            CloseButtonText = "Cancelar",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) Run(package.UninstallCommand);
    }

    private void OnInstall(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is CatalogTool tool) Run(tool.InstallCommand);
    }

    /// <summary>Runs in the chat, and goes back to it so the output is in view.</summary>
    private void Run(string command)
    {
        App.Controller.RunPackageCommand(command);
        BackRequested?.Invoke();
    }
}
