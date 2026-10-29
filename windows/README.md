# Comando para Windows

Versión nativa para Windows hecha con WinUI 3 y .NET 10. Las decisiones, el mapeo desde macOS y las fases están en [docs/windows/STACK.md](../docs/windows/STACK.md).

## Requisitos

- Windows 11 (Windows 10 2004 o posterior funciona sin Mica).
- [Visual Studio 2022](https://visualstudio.microsoft.com/) 17.14 o posterior con la carga de trabajo **Desarrollo de aplicaciones WinUI**, o solo el [SDK de .NET 10](https://dotnet.microsoft.com/download/dotnet/10.0).
- PowerShell 7 (recomendado). Sin él, Comando usa Windows PowerShell 5.1 y ofrece instalarlo.

```powershell
winget install --id Microsoft.PowerShell --source winget
```

## Compilar y abrir

En Visual Studio: abre `Comando.Windows.slnx`, elige `Comando.App` como proyecto de inicio y la plataforma `x64` (o `ARM64`), y presiona F5. La app se instala como paquete MSIX de desarrollo.

Desde la terminal:

```powershell
dotnet build windows/src/Comando.App/Comando.App.csproj -c Debug -p:Platform=x64
```

## Pruebas

El núcleo (`Comando.Core`) no depende de Windows, así que sus pruebas corren en cualquier sistema, también en el Mac:

```bash
dotnet test windows/tests/Comando.Core.Tests
```

La CI (`.github/workflows/windows.yml`) corre esas pruebas y compila la app en `windows-latest` en cada push que toque `windows/`.

## Qué funciona en esta fase

- Ventana con Mica, barra de título propia con búsqueda y barra lateral de sesiones (fijar, renombrar, borrar historial, abrir en el Explorador de archivos).
- Comandos de PowerShell como mensajes, con colores ANSI, salida en vivo y “Mostrar todo” para salidas largas.
- Confirmación antes de comandos riesgosos, con la opción de enviar a la Papelera de reciclaje en vez de borrar.
- Historial guardado en `%LocalAppData%\Comando\sessions.json`.

Los programas de pantalla completa (`vim`, `ssh`, agentes de IA) todavía no tienen terminal integrada: la burbuja lo dice y se pueden detener o responder desde el campo de texto.
