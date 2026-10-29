namespace Comando.Core.Language;

/// <summary>The built-in recipes, written for PowerShell on Windows, searchable by what people want to do.</summary>
public static class RecipeBook
{
    public static IReadOnlyList<Recipe> Search(string query) => All.Where(recipe => recipe.Matches(query)).ToList();

    public static Recipe? Find(string id) => All.FirstOrDefault(recipe => recipe.Id == id);

    private static string Q(string value) => ShellWords.Quote(value);

    private static string Digits(string value) => new(value.Where(char.IsDigit).ToArray());

    private static RecipeParameter[] One(string id, string label, RecipeParameterKind kind, string placeholder, string? defaultValue = null) =>
        [new RecipeParameter(id, label, kind, placeholder, defaultValue)];

    public static readonly IReadOnlyList<Recipe> All =
    [
        // Archivos y carpetas
        new Recipe("list", "Ver qué hay en esta carpeta", "Lista los archivos con su tamaño y fecha.", "", RecipeCategory.Files,
            _ => "Get-ChildItem",
            keywords: ["listar", "archivos", "contenido", "ls", "dir"]),
        new Recipe("hidden", "Ver archivos ocultos", "Incluye los ocultos y los del sistema, como .gitignore.", "", RecipeCategory.Files,
            _ => "Get-ChildItem -Force",
            keywords: ["ocultos", "punto", "dotfiles"]),
        new Recipe("mkdir", "Crear una carpeta", "Crea una carpeta nueva aquí.", "", RecipeCategory.Files,
            v => "New-Item -ItemType Directory -Name " + Q(v["name"]),
            keywords: ["nueva", "directorio"],
            parameters: One("name", "Nombre", RecipeParameterKind.Text, "Nueva carpeta")),
        new Recipe("touch", "Crear un archivo vacío", "Crea un archivo nuevo aquí.", "", RecipeCategory.Files,
            v => "New-Item -ItemType File -Name " + Q(v["name"]),
            keywords: ["nuevo", "texto"],
            parameters: One("name", "Nombre", RecipeParameterKind.Text, "notas.txt")),
        new Recipe("find", "Buscar archivos por nombre", "Busca en esta carpeta y en las que tiene dentro.", "", RecipeCategory.Files,
            v => "Get-ChildItem -Recurse -Filter " + Q($"*{v["text"]}*") + " | Select-Object -ExpandProperty FullName",
            keywords: ["encontrar", "nombre"],
            parameters: One("text", "Parte del nombre", RecipeParameterKind.Text, "informe")),
        new Recipe("grep", "Buscar texto dentro de archivos", "Muestra cada archivo y línea donde aparece el texto.", "", RecipeCategory.Files,
            v => "Get-ChildItem -Recurse -File | Select-String -SimpleMatch -Pattern " + Q(v["text"]),
            keywords: ["contenido", "palabra", "grep", "select-string"],
            parameters: One("text", "Texto", RecipeParameterKind.Text, "TODO")),
        new Recipe("du", "Ver qué ocupa más espacio aquí", "Ordena lo que hay en esta carpeta por tamaño.", "", RecipeCategory.Files,
            _ => "Get-ChildItem -Force | ForEach-Object { $size = if ($_.PSIsContainer) { (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { $_.Length }; [pscustomobject]@{ Nombre = $_.Name; MB = [math]::Round($size / 1MB, 1) } } | Sort-Object MB -Descending | Select-Object -First 20",
            keywords: ["tamaño", "espacio", "pesado", "grande"]),
        new Recipe("zip", "Comprimir una carpeta", "Crea un archivo .zip con la carpeta elegida.", "", RecipeCategory.Files,
            v =>
            {
                // Split by hand: the core also runs on macOS, where \\ isn't a separator.
                var name = v["folder"].TrimEnd('\\', '/').Split('\\', '/')[^1];
                return "Compress-Archive -Path " + Q(v["folder"]) + " -DestinationPath " + Q(name + ".zip");
            },
            keywords: ["zip", "comprimir", "empaquetar"],
            parameters: One("folder", "Carpeta", RecipeParameterKind.Folder, "carpeta")),
        new Recipe("unzip", "Descomprimir un .zip", "Extrae el contenido aquí.", "", RecipeCategory.Files,
            v => "Expand-Archive -Path " + Q(v["file"]) + " -DestinationPath .",
            keywords: ["zip", "extraer", "descomprimir"],
            parameters: One("file", "Archivo .zip", RecipeParameterKind.File, "archivo.zip")),
        new Recipe("explorer", "Abrir esta carpeta en el Explorador de archivos", "Muestra la carpeta actual en una ventana del Explorador.", "", RecipeCategory.Files,
            _ => "explorer .",
            keywords: ["explorador", "abrir", "ventana", "finder"]),
        new Recipe("copypath", "Copiar la ruta de esta carpeta", "Deja la ruta en el portapapeles.", "", RecipeCategory.Files,
            _ => "(Get-Location).Path | Set-Clipboard",
            keywords: ["ruta", "path", "copiar"]),

        // Tu PC
        new Recipe("df", "Ver el espacio en disco", "Cuánto espacio queda libre en cada disco.", "", RecipeCategory.System,
            _ => "Get-PSDrive -PSProvider FileSystem",
            keywords: ["disco", "libre", "almacenamiento"]),
        new Recipe("winver", "Ver la versión de Windows", "Nombre, versión y compilación del sistema.", "", RecipeCategory.System,
            _ => "Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber",
            keywords: ["versión", "sistema", "windows"]),
        new Recipe("cpu", "Ver qué está usando más CPU", "Los 10 programas que más procesador han usado.", "", RecipeCategory.System,
            _ => "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Id, ProcessName, CPU",
            keywords: ["lento", "procesos", "cpu", "procesador"]),
        new Recipe("memory", "Ver qué está usando más memoria", "Los 10 programas que más RAM ocupan.", "", RecipeCategory.System,
            _ => "Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Id, ProcessName, @{ Name = 'MB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB) } }",
            keywords: ["ram", "memoria", "procesos", "lento"]),
        new Recipe("date", "Ver la fecha y la hora", "La fecha y hora de este PC.", "", RecipeCategory.System,
            _ => "Get-Date",
            keywords: ["hora", "fecha", "dia", "hoy"]),
        new Recipe("battery", "Ver el estado de la batería", "Porcentaje de carga y estado.", "", RecipeCategory.System,
            _ => "Get-CimInstance Win32_Battery | Select-Object EstimatedChargeRemaining, BatteryStatus",
            keywords: ["batería", "carga"]),
        new Recipe("awake", "Evitar que el PC se duerma", "Mantiene el PC y la pantalla despiertos hasta que lo detengas.", "", RecipeCategory.System,
            _ => "if (-not ('Comando.Awake' -as [type])) { Add-Type -Namespace Comando -Name Awake -MemberDefinition '[DllImport(\"kernel32.dll\")] public static extern uint SetThreadExecutionState(uint flags);' }; [void][Comando.Awake]::SetThreadExecutionState(0x80000003); Write-Host 'El PC no se dormirá hasta que detengas este comando.'; while ($true) { Start-Sleep -Seconds 60 }",
            keywords: ["dormir", "suspender", "reposo", "despierto", "caffeinate"]),
        new Recipe("upgradable", "Ver qué programas se pueden actualizar", "Los programas con una versión nueva, según winget.", "", RecipeCategory.System,
            _ => "winget upgrade",
            keywords: ["actualizar", "versiones", "winget", "programas"]),
        new Recipe("upgradeall", "Actualizar todos los programas", "Instala las versiones nuevas que encuentre winget.", "", RecipeCategory.System,
            _ => "winget upgrade --all",
            keywords: ["actualizar", "todo", "winget", "programas"]),

        // Red
        new Recipe("port", "Ver qué programa usa un puerto", "Útil cuando un servidor dice que el puerto está ocupado.", "", RecipeCategory.Network,
            v => "Get-NetTCPConnection -LocalPort " + Digits(v["port"]) + " -State Listen | ForEach-Object { Get-Process -Id $_.OwningProcess }",
            keywords: ["puerto", "ocupado", "port", "eaddrinuse"],
            parameters: One("port", "Puerto", RecipeParameterKind.Number, "3000")),
        new Recipe("ip", "Ver mi dirección IP local", "La dirección de este PC en tu red.", "", RecipeCategory.Network,
            _ => "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object InterfaceAlias, IPAddress",
            keywords: ["ip", "dirección", "red", "wifi"]),
        new Recipe("dns", "Vaciar la caché de DNS", "Ayuda cuando una página no carga tras cambiar de dirección. Puede pedir permisos de administrador.", "", RecipeCategory.Network,
            _ => "Clear-DnsClientCache",
            keywords: ["dns", "cache", "flush", "internet", "pagina"]),
        new Recipe("ping", "Probar la conexión a internet", "Envía 4 mensajes de prueba a microsoft.com.", "", RecipeCategory.Network,
            _ => "Test-Connection microsoft.com -Count 4",
            keywords: ["internet", "conexión", "ping"]),
        new Recipe("serve", "Compartir esta carpeta como sitio web", "Inicia un servidor local; ábrelo en el navegador.", "", RecipeCategory.Network,
            v =>
            {
                var port = Digits(v["port"]);
                return $"if (Get-Command python -ErrorAction SilentlyContinue) {{ python -m http.server {port} }} else {{ npx --yes serve -l {port} }}";
            },
            keywords: ["servidor", "web", "http", "local"],
            parameters: One("port", "Puerto", RecipeParameterKind.Number, "8000", "8000")),

        // Desarrollo
        new Recipe("gitstatus", "Ver los cambios del proyecto", "Qué archivos cambiaste desde el último commit.", "", RecipeCategory.Development,
            _ => "git status",
            keywords: ["git", "cambios", "estado"]),
        new Recipe("gitlog", "Ver el historial reciente", "Los últimos 15 commits, uno por línea.", "", RecipeCategory.Development,
            _ => "git log --oneline -15",
            keywords: ["git", "historial", "commits"]),
        new Recipe("npminstall", "Instalar las dependencias", "Descarga lo que el proyecto necesita (npm).", "", RecipeCategory.Development,
            _ => "npm install",
            keywords: ["npm", "node", "instalar", "dependencias"]),
        new Recipe("npmrun", "Ver los scripts del proyecto", "Lista los comandos que define package.json.", "", RecipeCategory.Development,
            _ => "npm run",
            keywords: ["npm", "scripts", "package.json"]),
        new Recipe("versions", "Ver versiones de Node y Python", "Qué versiones están instaladas.", "", RecipeCategory.Development,
            _ => "node -v; python --version",
            keywords: ["node", "python", "versión"]),
    ];
}
