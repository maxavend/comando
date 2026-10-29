using System.Text;
using Comando.Core.Tools;

namespace Comando.Core.Tests;

public class WingetParserTests
{
    private static readonly int[] Widths = [39, 35, 15, 15];

    /// <summary>A line laid out like winget's table, so columns line up exactly.</summary>
    private static string Row(params string[] cells)
    {
        var builder = new StringBuilder();
        for (var i = 0; i < cells.Length; i++)
        {
            builder.Append(i < Widths.Length && i < cells.Length - 1 ? cells[i].PadRight(Widths[i]) : cells[i]);
        }
        return builder.ToString();
    }

    private static string Rule => new('-', Widths.Sum() + 6);

    [Fact]
    public void ListWithAvailableAndSource()
    {
        var output = string.Join("\r\n",
            "   - \r   \\ \r   | \r",
            Row("Name", "Id", "Version", "Available", "Source"),
            Rule,
            Row("Git", "Git.Git", "2.43.0", "2.44.0", "winget"),
            Row("Microsoft Visual Studio Code", "Microsoft.VisualStudioCode", "1.86.2", "", "winget"),
            Row("Some Very Long Application Name That…", "Contoso.VeryLongApplicationNam…", "1.0", "1.1", "winget"),
            Row("Windows Notepad", "9MSMLRH6LZF3", "11.2312.18.0", "", "msstore"),
            Row("Old Driver", "ARP\\Machine\\X64\\OldDriver", "3.1", "", ""),
            "3 upgrades available.");

        var packages = PackageParsers.Winget(output);

        Assert.Equal(5, packages.Count);
        var git = packages[0];
        Assert.Equal("Git", git.Name);
        Assert.Equal("Git.Git", git.Id);
        Assert.Equal("2.43.0", git.Version);
        Assert.Equal("2.44.0", git.LatestVersion);
        Assert.True(git.IsOutdated);
        Assert.Equal("winget", git.Source);

        Assert.False(packages[1].IsOutdated);
        Assert.Null(packages[1].LatestVersion);

        var truncated = packages[2];
        Assert.True(truncated.IsIdTruncated);
        Assert.Equal("Contoso.VeryLongApplicationNam", truncated.Id);
        Assert.Equal("Some Very Long Application Name That", truncated.Name);
        Assert.DoesNotContain("--exact", truncated.UpgradeCommand);
        Assert.Contains("--exact", git.UpgradeCommand);

        Assert.Equal("msstore", packages[3].Source);
        Assert.Equal("", packages[4].Source);
    }

    [Fact]
    public void UpgradeReadsBothTables()
    {
        var output = string.Join("\n",
            Row("Nombre", "Id", "Versión", "Disponible", "Origen"),
            Rule,
            Row("Git", "Git.Git", "2.43.0", "2.44.0", "winget"),
            "1 actualizaciones disponibles.",
            "",
            "Los siguientes paquetes tienen una actualización disponible, pero requieren un destino explícito para la actualización:",
            Row("Nombre", "Id", "Versión", "Disponible", "Origen"),
            Rule,
            Row("Discord", "Discord.Discord", "1.0.9030", "1.0.9035", "winget"));

        var packages = PackageParsers.Winget(output);

        Assert.Equal(new[] { "Git.Git", "Discord.Discord" }, packages.Select(p => p.Id).ToArray());
        Assert.All(packages, p => Assert.True(p.IsOutdated));
    }

    [Fact]
    public void FourColumnsWithoutAvailable()
    {
        var output = string.Join("\n",
            Row("Name", "Id", "Version", "Source"),
            Rule,
            Row("Git", "Git.Git", "2.43.0", "winget"));

        var package = Assert.Single(PackageParsers.Winget(output));
        Assert.Null(package.LatestVersion);
        Assert.Equal("winget", package.Source);
    }

    [Fact]
    public void NothingInstalled()
    {
        Assert.Empty(PackageParsers.Winget("No installed package found matching input criteria."));
    }
}

public class ScoopParserTests
{
    [Fact]
    public void List()
    {
        const string output = """
            Installed apps:

            Name    Version Source Updated             Info
            ----    ------- ------ -------             ----
            7zip    23.01   main   2024-01-10 10:00:00
            git     2.43.0  main   2024-01-10 10:01:12
            nodejs  21.6.1  main   2024-02-01 09:30:45 Global install
            """;

        var packages = PackageParsers.ScoopList(output);

        Assert.Equal(new[] { "7zip", "git", "nodejs" }, packages.Select(p => p.Name).ToArray());
        Assert.Equal("23.01", packages[0].Version);
        Assert.Equal("main", packages[1].Source);
        Assert.Equal(PackageManager.Scoop, packages[2].Manager);
    }

    [Fact]
    public void Status()
    {
        const string output = """
            Scoop is up to date.

            Name    Installed Version Latest Version Missing Dependencies Info
            ----    ----------------- -------------- -------------------- ----
            git     2.43.0            2.44.0
            nodejs  21.6.1            21.7.0
            """;

        var latest = PackageParsers.ScoopStatus(output);

        Assert.Equal("2.44.0", latest["git"]);
        Assert.Equal("21.7.0", latest["nodejs"]);
    }
}

public class NpmParserTests
{
    [Fact]
    public void List()
    {
        const string json = """
            {
              "name": "lib",
              "dependencies": {
                "@angular/cli": { "version": "17.1.2", "overridden": false },
                "npm": { "version": "10.2.4" },
                "typescript": { "version": "5.3.3" }
              }
            }
            """;

        var packages = PackageParsers.NpmList(json);

        Assert.Equal(new[] { "@angular/cli", "npm", "typescript" }, packages.Select(p => p.Id).ToArray());
        Assert.Equal("5.3.3", packages[2].Version);
        Assert.Equal("npm install -g '@angular/cli@latest'", packages[0].UpgradeCommand);
    }

    [Fact]
    public void ListOfAnotherNodeUsesItsOwnNpm()
    {
        const string json = """{ "dependencies": { "pnpm": { "version": "8.15.1" } } }""";

        var package = Assert.Single(PackageParsers.NpmList(json, "18.19.0", @"C:\nvm\v18.19.0\npm.cmd", isActiveNode: false));

        Assert.Equal(@"& C:\nvm\v18.19.0\npm.cmd uninstall -g pnpm", package.UninstallCommand);
        Assert.Equal("npm global · Node 18.19.0", package.Origin);
    }

    [Fact]
    public void Outdated()
    {
        const string json = """
            npm WARN config global `--global`, `--local` are deprecated.
            {
              "typescript": { "current": "5.3.3", "wanted": "5.4.2", "latest": "5.4.2", "dependent": "global", "location": "C:\\Users\\max\\AppData\\Roaming\\npm\\node_modules\\typescript" },
              "npm": { "current": "10.2.4", "wanted": "10.2.4", "latest": "10.2.4" }
            }
            """;

        var latest = PackageParsers.NpmOutdated(json);

        Assert.Equal("5.4.2", latest["typescript"]);
        Assert.False(latest.ContainsKey("npm"));
    }

    [Fact]
    public void BrokenJsonIsEmpty()
    {
        Assert.Empty(PackageParsers.NpmList("npm ERR! something went wrong"));
        Assert.Empty(PackageParsers.NpmOutdated(""));
    }
}

public class PythonToolParserTests
{
    [Fact]
    public void PipxList()
    {
        const string json = """
            {
              "pipx_spec_version": "0.1",
              "venvs": {
                "black": {
                  "metadata": {
                    "main_package": { "package": "black", "package_version": "24.1.1", "apps": ["black.exe", "blackd.exe"] }
                  }
                },
                "httpie": {
                  "metadata": {
                    "main_package": { "package": "httpie", "package_version": "3.2.2", "apps": ["http.exe", "https.exe"] }
                  }
                }
              }
            }
            """;

        var packages = PackageParsers.PipxList(json);

        Assert.Equal(new[] { "black", "httpie" }, packages.Select(p => p.Name).ToArray());
        Assert.Equal("24.1.1", packages[0].Version);
        Assert.Equal(new[] { "http", "https" }, packages[1].Commands.ToArray());
        Assert.Equal("pipx upgrade black", packages[0].UpgradeCommand);
    }

    [Fact]
    public void UvToolList()
    {
        const string output = """
            ruff v0.3.0
            - ruff.exe
            httpie v3.2.2
            - http.exe
            - https.exe
            """;

        var packages = PackageParsers.UvToolList(output);

        Assert.Equal(new[] { "ruff", "httpie" }, packages.Select(p => p.Name).ToArray());
        Assert.Equal("0.3.0", packages[0].Version);
        Assert.Equal(new[] { "ruff" }, packages[0].Commands.ToArray());
        Assert.Equal(new[] { "http", "https" }, packages[1].Commands.ToArray());
        Assert.Null(packages[0].LatestVersion);
    }

    [Fact]
    public void UvToolListOutdated()
    {
        const string output = """
            warning: `uv tool list --outdated` is experimental and may change without warning.
            ruff v0.3.0 [latest: 0.4.1]
            - ruff.exe
            """;

        var package = Assert.Single(PackageParsers.UvToolList(output));

        Assert.Equal("0.4.1", package.LatestVersion);
        Assert.True(package.IsOutdated);
    }

    [Fact]
    public void UvNoTools()
    {
        Assert.Empty(PackageParsers.UvToolList("No tools installed"));
    }
}

public class PackageCommandTests
{
    [Fact]
    public void CommandsPerManager()
    {
        var winget = new InstalledPackage(PackageManager.Winget, "Git", "Git.Git", "2.43.0", "2.44.0");
        Assert.Equal("winget upgrade --id Git.Git --exact --accept-source-agreements --accept-package-agreements", winget.UpgradeCommand);
        Assert.Equal("winget uninstall --id Git.Git --exact --accept-source-agreements", winget.UninstallCommand);
        Assert.Equal("winget install --id Gyan.FFmpeg --exact --source winget --accept-source-agreements --accept-package-agreements",
            PackageManager.Winget.InstallCommand("Gyan.FFmpeg"));

        var scoop = new InstalledPackage(PackageManager.Scoop, "git", "git", "2.43.0");
        Assert.Equal("scoop update git", scoop.UpgradeCommand);
        Assert.Equal("scoop update '*'", PackageManager.Scoop.UpgradeAllCommand());

        Assert.Equal("uv tool upgrade --all", PackageManager.Uv.UpgradeAllCommand());
        Assert.Equal("pipx upgrade-all", PackageManager.Pipx.UpgradeAllCommand());
        Assert.Equal("npm update -g", PackageManager.Npm.UpgradeAllCommand());
    }

    [Fact]
    public void IdsWithBracesAreQuoted()
    {
        var package = new InstalledPackage(PackageManager.Winget, "Old Driver", @"ARP\Machine\X64\{1234}", "3.1");
        Assert.Equal(@"winget uninstall --id 'ARP\Machine\X64\{1234}' --exact --accept-source-agreements", package.UninstallCommand);
    }
}

public class ToolCatalogTests
{
    [Fact]
    public void FindsByWhatPeopleWantToDo()
    {
        Assert.Equal("Gyan.FFmpeg", ToolCatalog.Search("convertir un video a mp4")[0].Id);
        Assert.Equal("7zip.7zip", ToolCatalog.Search("descomprimir un rar")[0].Id);
        Assert.Equal("yt-dlp.yt-dlp", ToolCatalog.Search("descargar de YouTube")[0].Id);
    }

    [Fact]
    public void FindsByCommand()
    {
        Assert.Equal("BurntSushi.ripgrep.MSVC", ToolCatalog.ProvidingCommand("rg")?.Id);
        Assert.Equal("Gyan.FFmpeg", ToolCatalog.Search("ffmpeg")[0].Id);
    }

    [Fact]
    public void EveryToolCanBeInstalled()
    {
        Assert.True(ToolCatalog.All.Count >= 40);
        Assert.All(ToolCatalog.All, tool => Assert.False(string.IsNullOrWhiteSpace(tool.InstallCommand)));
        Assert.Equal(ToolCatalog.All.Count, ToolCatalog.All.Select(t => t.Id).Distinct().Count());
    }

    [Fact]
    public void IgnoresAccents()
    {
        Assert.Contains(ToolCatalog.Search("imágenes"), tool => tool.Id == "ImageMagick.ImageMagick");
    }
}

public class PathLookupTests
{
    [Fact]
    public void FindsBatchFiles()
    {
        var folder = Directory.CreateTempSubdirectory("comando-path-").FullName;
        try
        {
            File.WriteAllText(Path.Combine(folder, "npm.cmd"), "@echo off");
            Assert.Equal(Path.Combine(folder, "npm.cmd"), PathLookup.Find("npm", new[] { folder }));
            Assert.Null(PathLookup.Find("pipx", new[] { folder }));
        }
        finally
        {
            Directory.Delete(folder, recursive: true);
        }
    }
}
