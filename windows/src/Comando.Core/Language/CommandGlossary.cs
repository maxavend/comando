namespace Comando.Core.Language;

/// <summary>Plain-language descriptions of common commands, shown under the command bubble.</summary>
public static class CommandGlossary
{
    public static string? Describe(string command)
    {
        var words = command.Split([' ', '\n'], StringSplitOptions.RemoveEmptyEntries).ToList();
        // Skip variable assignments ($x = …) and the call operator (& .\script.ps1).
        while (words.Count > 0 && (words[0] == "&" || words[0] == "."))
        {
            words.RemoveAt(0);
        }
        if (words.Count == 0) return null;
        if (words[0].StartsWith('$'))
        {
            return words.Count > 1 && words[1] == "=" ? "Guardar un valor en una variable" : "Mostrar el valor de una variable";
        }
        var name = ShellWords.ProgramName(words[0]);
        if (name.Length == 0) return null;
        var subcommand = words.Skip(1).FirstOrDefault(word => !word.StartsWith('-'));

        if (Subcommands.TryGetValue(name, out var table) && subcommand is not null
            && table.TryGetValue(subcommand, out var described))
        {
            return described;
        }
        return Commands.GetValueOrDefault(name) ?? Commands.GetValueOrDefault(Canonical(name));
    }

    /// <summary>
    /// The cmdlet an alias stands for (<c>ls</c> → <c>get-childitem</c>), lowercased,
    /// so options are looked up in one place.
    /// </summary>
    public static string Canonical(string program)
    {
        var name = ShellWords.ProgramName(program);
        return Aliases.GetValueOrDefault(name, name);
    }

    private static readonly Dictionary<string, string> Aliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["ls"] = "get-childitem", ["dir"] = "get-childitem", ["gci"] = "get-childitem",
        ["cd"] = "set-location", ["sl"] = "set-location", ["chdir"] = "set-location",
        ["pwd"] = "get-location", ["gl"] = "get-location",
        ["rm"] = "remove-item", ["del"] = "remove-item", ["erase"] = "remove-item", ["ri"] = "remove-item", ["rd"] = "remove-item", ["rmdir"] = "remove-item",
        ["cp"] = "copy-item", ["copy"] = "copy-item", ["cpi"] = "copy-item",
        ["mv"] = "move-item", ["move"] = "move-item", ["mi"] = "move-item",
        ["ren"] = "rename-item", ["rni"] = "rename-item",
        ["cat"] = "get-content", ["type"] = "get-content", ["gc"] = "get-content",
        ["echo"] = "write-output", ["write"] = "write-output",
        ["cls"] = "clear-host", ["clear"] = "clear-host",
        ["ps"] = "get-process", ["gps"] = "get-process",
        ["kill"] = "stop-process", ["spps"] = "stop-process",
        ["sls"] = "select-string",
        ["select"] = "select-object",
        ["where"] = "where-object", ["?"] = "where-object",
        ["foreach"] = "foreach-object", ["%"] = "foreach-object",
        ["sort"] = "sort-object",
        ["ii"] = "invoke-item", ["start"] = "start-process", ["saps"] = "start-process",
        ["iwr"] = "invoke-webrequest",
        ["irm"] = "invoke-restmethod",
        ["iex"] = "invoke-expression",
        ["md"] = "mkdir",
        ["ni"] = "new-item",
        ["h"] = "get-history", ["history"] = "get-history",
        ["man"] = "get-help", ["help"] = "get-help",
        ["gcm"] = "get-command",
    };

    private static readonly Dictionary<string, string> Commands = new(StringComparer.OrdinalIgnoreCase)
    {
        // PowerShell cmdlets
        ["get-childitem"] = "Listar archivos",
        ["set-location"] = "Cambiar de carpeta",
        ["get-location"] = "Mostrar la carpeta actual",
        ["new-item"] = "Crear un archivo o carpeta",
        ["mkdir"] = "Crear una carpeta",
        ["remove-item"] = "Eliminar archivos",
        ["papelera"] = "Enviar a la Papelera de reciclaje",
        ["copy-item"] = "Copiar archivos",
        ["move-item"] = "Mover archivos",
        ["rename-item"] = "Cambiar el nombre",
        ["get-content"] = "Mostrar el contenido de un archivo",
        ["set-content"] = "Escribir en un archivo",
        ["add-content"] = "Agregar texto a un archivo",
        ["out-file"] = "Guardar el resultado en un archivo",
        ["write-output"] = "Mostrar un texto",
        ["write-host"] = "Mostrar un texto",
        ["clear-host"] = "Limpiar la conversación",
        ["get-process"] = "Listar programas en ejecución",
        ["stop-process"] = "Cerrar un programa",
        ["start-process"] = "Abrir un programa o archivo",
        ["invoke-item"] = "Abrir con la app predeterminada",
        ["select-string"] = "Buscar texto",
        ["select-object"] = "Elegir qué columnas o cuántos resultados mostrar",
        ["where-object"] = "Filtrar los resultados",
        ["foreach-object"] = "Hacer algo con cada resultado",
        ["sort-object"] = "Ordenar los resultados",
        ["measure-object"] = "Contar o sumar los resultados",
        ["format-table"] = "Mostrar como tabla",
        ["format-list"] = "Mostrar como lista",
        ["invoke-webrequest"] = "Consultar o descargar una URL",
        ["invoke-restmethod"] = "Consultar una API web",
        ["invoke-expression"] = "Ejecutar un texto como comando",
        ["test-connection"] = "Probar la conexión con un equipo",
        ["test-path"] = "Ver si existe un archivo o carpeta",
        ["get-command"] = "Ubicar un comando",
        ["get-help"] = "Ver la ayuda de un comando",
        ["get-history"] = "Ver comandos anteriores",
        ["get-date"] = "Ver la fecha y la hora",
        ["get-psdrive"] = "Ver los discos y su espacio",
        ["get-computerinfo"] = "Ver información del sistema",
        ["get-ciminstance"] = "Consultar información del sistema",
        ["get-netipaddress"] = "Ver las direcciones de red",
        ["get-nettcpconnection"] = "Ver las conexiones de red",
        ["clear-dnsclientcache"] = "Vaciar la caché de DNS",
        ["compress-archive"] = "Comprimir en un .zip",
        ["expand-archive"] = "Descomprimir un .zip",
        ["set-clipboard"] = "Copiar al portapapeles",
        ["get-clipboard"] = "Pegar desde el portapapeles",
        ["start-sleep"] = "Esperar unos segundos",
        ["set-executionpolicy"] = "Cambiar qué scripts se pueden ejecutar",
        ["install-module"] = "Instalar un módulo de PowerShell",
        // Windows programs
        ["explorer"] = "Abrir el Explorador de archivos",
        ["notepad"] = "Abrir el Bloc de notas",
        ["ipconfig"] = "Ver la configuración de red",
        ["ping"] = "Probar la conexión con un equipo",
        ["tracert"] = "Ver el camino hasta un equipo",
        ["netstat"] = "Ver las conexiones de red",
        ["tasklist"] = "Listar programas en ejecución",
        ["taskkill"] = "Cerrar un programa",
        ["where.exe"] = "Ubicar un programa",
        ["whoami"] = "Ver tu usuario",
        ["hostname"] = "Ver el nombre del PC",
        ["systeminfo"] = "Ver información del sistema",
        ["shutdown"] = "Apagar o reiniciar el PC",
        ["ssh"] = "Conectarse a otro equipo",
        ["curl"] = "Consultar o descargar una URL",
        ["scp"] = "Copiar archivos a otro equipo",
        ["tar"] = "Empaquetar o desempaquetar archivos",
        ["code"] = "Abrir en Visual Studio Code",
        // Tools
        ["git"] = "Control de versiones con Git",
        ["winget"] = "Gestionar programas con winget",
        ["scoop"] = "Gestionar programas con Scoop",
        ["choco"] = "Gestionar programas con Chocolatey",
        ["npm"] = "Gestionar paquetes de Node.js",
        ["npx"] = "Ejecutar un paquete de Node.js",
        ["pnpm"] = "Gestionar paquetes de Node.js",
        ["yarn"] = "Gestionar paquetes de Node.js",
        ["node"] = "Ejecutar Node.js",
        ["python"] = "Ejecutar Python",
        ["py"] = "Ejecutar Python",
        ["pip"] = "Gestionar paquetes de Python",
        ["pipx"] = "Instalar herramientas de Python",
        ["uv"] = "Gestionar proyectos y herramientas de Python",
        ["docker"] = "Gestionar contenedores con Docker",
        ["dotnet"] = "Compilar y ejecutar proyectos .NET",
        ["wsl"] = "Usar Linux dentro de Windows",
        ["vim"] = "Editar un archivo",
        ["nvim"] = "Editar un archivo",
        ["edit"] = "Editar un archivo",
    };

    private static readonly Dictionary<string, Dictionary<string, string>> Subcommands = new(StringComparer.OrdinalIgnoreCase)
    {
        ["git"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["status"] = "Ver los cambios del repositorio",
            ["log"] = "Ver el historial de cambios",
            ["diff"] = "Ver las diferencias",
            ["add"] = "Preparar cambios para guardar",
            ["commit"] = "Guardar los cambios",
            ["push"] = "Subir los cambios",
            ["pull"] = "Traer los últimos cambios",
            ["clone"] = "Descargar un repositorio",
            ["checkout"] = "Cambiar de rama o restaurar archivos",
            ["switch"] = "Cambiar de rama",
            ["branch"] = "Ver o crear ramas",
            ["merge"] = "Unir una rama",
            ["stash"] = "Guardar cambios temporalmente",
            ["init"] = "Crear un repositorio",
            ["fetch"] = "Consultar cambios remotos",
        },
        ["winget"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["install"] = "Instalar un programa",
            ["uninstall"] = "Desinstalar un programa",
            ["upgrade"] = "Actualizar programas",
            ["list"] = "Ver programas instalados",
            ["search"] = "Buscar un programa",
            ["show"] = "Ver información de un programa",
        },
        ["scoop"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["install"] = "Instalar un programa",
            ["uninstall"] = "Desinstalar un programa",
            ["update"] = "Actualizar programas",
            ["list"] = "Ver programas instalados",
            ["search"] = "Buscar un programa",
        },
        ["npm"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["install"] = "Instalar dependencias",
            ["i"] = "Instalar dependencias",
            ["run"] = "Ejecutar un script del proyecto",
            ["test"] = "Ejecutar las pruebas",
            ["start"] = "Iniciar el proyecto",
            ["uninstall"] = "Quitar un paquete",
            ["update"] = "Actualizar paquetes",
        },
        ["pip"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["install"] = "Instalar un paquete de Python",
            ["uninstall"] = "Quitar un paquete de Python",
            ["list"] = "Ver paquetes de Python instalados",
        },
        ["docker"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["ps"] = "Ver los contenedores en marcha",
            ["run"] = "Iniciar un contenedor",
            ["build"] = "Construir una imagen",
            ["images"] = "Ver las imágenes",
            ["stop"] = "Detener un contenedor",
            ["compose"] = "Gestionar varios contenedores juntos",
        },
        ["dotnet"] = new(StringComparer.OrdinalIgnoreCase)
        {
            ["build"] = "Compilar el proyecto",
            ["run"] = "Ejecutar el proyecto",
            ["test"] = "Ejecutar las pruebas",
            ["new"] = "Crear un proyecto",
        },
    };

    /// <summary>Programs whose first argument is an action of their own (<c>git commit</c>).</summary>
    internal static bool HasSubcommands(string program) => Subcommands.ContainsKey(program);
}
