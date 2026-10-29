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

## Instalar sin compilar

Las versiones publicadas están en [GitHub Releases](https://github.com/maxavend/comando/releases) (etiquetas `windows-vX.Y.Z`), y cada push genera las mismas descargas en GitHub Actions (pestaña **Actions** → la última ejecución de **Windows** → **Artifacts**), para x64 y ARM64:

- **Instalador** (`Comando-Windows-x64-setup.exe`): ábrelo; como no está firmado, la primera vez Windows dice «Windows protegió tu PC» → **Más información** → **Ejecutar de todos modos**. Se instala para tu usuario en `%LOCALAPPDATA%\Programs\Comando`, sin permisos de administrador, aparece en el menú Inicio y se desinstala desde **Configuración › Aplicaciones**. Como el portátil, sin Phi Silica.
- **Portátil** (`Comando-Windows-x64-portable.zip`): descomprime y abre `Comando.exe`. No instala nada. El asistente responde con la guía y las recetas, pero sin Phi Silica, porque el modelo necesita la app instalada como paquete.
- **MSIX** (`Comando-Windows-x64-msix.zip`): descomprime, clic derecho en `Instalar.ps1` → **Ejecutar con PowerShell**. Windows pide permiso de administrador una vez para confiar en el certificado de prueba. Esta es la versión con Phi Silica, en PCs Copilot+.

## Qué incluye

Lo mismo que en macOS: chat de comandos, terminal integrada, asistente, recetas, herramientas, agentes de IA como chat, ajustes y notificaciones. Lo que funciona distinto está en [docs/windows/STACK.md](../docs/windows/STACK.md#pendiente-o-distinto-de-macos).
