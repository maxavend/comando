# Comando para Windows: stack

La versión de Windows es una app nativa aparte, no una adaptación del código de macOS. Comparte el diseño, los textos y la lógica (cada parte portada a C#), pero no comparte código con la de Swift. Vive en [`windows/`](../../windows).

## Decisiones

| Tema | Decisión | Por qué |
| --- | --- | --- |
| Interfaz | **WinUI 3** (Windows App SDK 1.8) | Es la interfaz nativa actual de Windows y ya implementa Fluent: Mica, barra de título propia, controles y temas. |
| Lenguaje | **C# 14 / .NET 10** | Es el camino principal de WinUI 3: plantillas, documentación y la galería usan C#. |
| Patrón | MVVM con **CommunityToolkit.Mvvm** | Equivale a `@Observable`: propiedades que avisan a la interfaz cuando cambian. |
| Shell | **PowerShell 7** (`pwsh`); si no está, Windows PowerShell 5.1 | Es la shell moderna de Windows y permite la integración que saca cada comando como mensaje. |
| Terminal | **ConPTY** (`CreatePseudoConsole`) | Equivale a la PTY de macOS: los programas creen que corren en una consola real, con colores y todo. |
| Asistente | **Phi Silica** (Windows AI, `Microsoft.Windows.AI.Text`) | Modelo local, igual de privado que Apple Intelligence. Solo en PCs Copilot+; en el resto quedan la guía y las recetas. |
| Datos | JSON en `%LocalAppData%\Comando` | Simple para empezar. Si el historial crece, se pasa a SQLite (`Microsoft.Data.Sqlite`). |
| Distribución | MSIX empaquetado | Phi Silica exige identidad de paquete. Después: instalador firmado o Microsoft Store. |
| Pruebas | xUnit para `Comando.Core`; compilación en GitHub Actions (`windows-latest`) | El núcleo no depende de Windows: sus pruebas corren en cualquier sistema. |

## Estructura

```
windows/
├── Comando.Windows.slnx
├── src/
│   ├── Comando.Core/      lógica sin interfaz: parser ANSI, búfer de líneas, sesión de shell,
│   │                      integración con PowerShell, ConPTY, detector de riesgos, modelos y guardado
│   └── Comando.App/       app WinUI 3: ventana, barra lateral, chat, campo de texto, diálogos
└── tests/
    └── Comando.Core.Tests/
```

`Comando.Core` apunta a `net10.0`, no a `net10.0-windows`. Así sus pruebas corren también en el Mac (`dotnet test`). La parte que llama a Windows (ConPTY) está marcada con `[SupportedOSPlatform("windows")]`.

## De macOS a Windows

| macOS (Swift) | Windows (C#) |
| --- | --- |
| SwiftUI, `NavigationSplitView` | WinUI 3, `Grid` con barra lateral y detalle ([Navegación](https://learn.microsoft.com/windows/apps/design/basics/navigation-basics)) |
| Liquid Glass / material de ventana | [Mica](https://learn.microsoft.com/windows/apps/design/style/mica) (`MicaBackdrop`); Acrylic en Windows 10 |
| Barra de título con búsqueda | [Barra de título propia](https://learn.microsoft.com/windows/apps/design/basics/titlebar-design) (`ExtendsContentIntoTitleBar`) con `AutoSuggestBox` |
| SF Symbols | [Segoe Fluent Icons](https://learn.microsoft.com/windows/apps/design/style/segoe-fluent-icons-font) (`FontIcon`, `SymbolIcon`) |
| SwiftData | Modelos `ObservableObject` + JSON (`SessionStore`) |
| zsh + `ZDOTDIR` con hooks `precmd`/`preexec` | `pwsh` + `comando.ps1`: función `prompt` y `PSConsoleHostReadLine` |
| PTY de SwiftTerm (`LocalProcess`) | `ConPtyTerminal` (P/Invoke a `kernel32`) |
| SwiftTerm (terminal integrada) | xterm.js dentro de WebView2 (`TerminalCard`) |
| Apple Intelligence (`FoundationModels`) | Phi Silica (`LanguageModel`), con la guía y las recetas como respaldo |
| `/usr/bin/trash` | Función `papelera` de la integración: envía a la Papelera de reciclaje |
| Homebrew, npm, pipx, uv | winget, Scoop, npm, pipx, uv |
| `UserNotifications` | Notificaciones de la app (`AppNotificationManager`) |
| `⌘` | `Ctrl` |

## Integración con PowerShell

El script `comando.ps1` se escribe en `%LocalAppData%\Comando\shell` cada vez que se abre la app y se carga después del perfil del usuario. Emite las mismas secuencias que la integración de zsh, así el resto del código no cambia:

| Secuencia | Cuándo | Cómo |
| --- | --- | --- |
| `OSC 133;C` | empieza la salida del comando | al final de `PSConsoleHostReadLine`, justo antes de devolver la línea |
| `OSC 6973;cwd;<ruta>` | carpeta actual | al principio de `prompt`; ruta de Windows tal cual, sin `file://` |
| `OSC 6973;path;<PATH>` | `$env:PATH` cambió | en `prompt` |
| `OSC 133;D;<código>` | terminó el comando | en `prompt`, después de la carpeta, con `$?` y `$LASTEXITCODE` |
| `OSC 133;A` | lista para el siguiente comando | al final de `prompt` |

PSReadLine no entiende el pegado entre corchetes (bracketed paste) que usa zsh para comandos de varias líneas. Por eso la app envía `#comando:<base64>`: `PSConsoleHostReadLine` lo decodifica y devuelve el comando original, que PowerShell ejecuta como si se hubiera escrito. Para PSReadLine es un comentario, así que no queda en el historial con esa forma.

## Estado

Todo lo de la versión de macOS está portado; lo distinto se explica abajo.

| Parte | Estado |
| --- | --- |
| Chat de comandos con PowerShell, colores, salida en vivo, “Mostrar todo” | Hecho |
| Sesiones: fijar, archivar, renombrar, ícono y color, búsqueda en la barra de título | Hecho |
| Terminal integrada (xterm.js en WebView2) para `vim`, `ssh`, REPL y agentes | Hecho |
| Asistente: guía, recetas y Phi Silica; adjuntar archivos arrastrándolos | Hecho |
| Pistas para comandos que fallan y “qué hace cada parte” | Hecho |
| Recetas (Ctrl+K) y “Mis recetas” guardadas desde el chat | Hecho |
| Herramientas (Ctrl+Mayús+I): winget, Scoop, npm, pipx, uv | Hecho |
| Agentes de IA como chat: `agy`, `claude`, `codex`, `qwen` | Hecho |
| Ajustes, bienvenida, notificaciones, Tab para completar | Hecho |
| Empaquetado: zip portátil y MSIX para x64 y ARM64 en la CI | Hecho |

## Pendiente o distinto de macOS

- **Contraseñas**: en macOS se detecta el eco apagado con `tcgetattr`. ConPTY no lo expone, así que el campo no se oculta al escribir una contraseña; conviene escribirla en la terminal integrada.
- **Detener un programa**: macOS manda señales al grupo de procesos. En Windows se envía `Ctrl+C` dos veces por la consola; un programa que lo ignora se detiene reiniciando la sesión.
- **Asistente sin Phi Silica**: en PCs que no son Copilot+, o con la versión portátil (sin paquete), responden la guía y las recetas, no el modelo.
- **Firma**: el MSIX de la CI está firmado con un certificado de prueba; `Instalar.ps1` lo agrega a los de confianza. Para publicar en Microsoft Store o instalar sin ese paso hace falta un certificado de firma de código real.
- **Ícono**: el actual tiene la forma de ícono de macOS; las guías de Windows piden otro estilo.

## Referencias de diseño

Las guías principales están en Microsoft Learn: [Design guidelines for Windows apps](https://learn.microsoft.com/windows/apps/design/), lo más parecido a las HIG. Cubren layout, navegación, tipografía, color, íconos, movimiento, materiales y cada control.

Las páginas que más sirven para Comando:

- [Barra de título](https://learn.microsoft.com/windows/apps/design/basics/titlebar-design): ahí va la búsqueda.
- [Mica](https://learn.microsoft.com/windows/apps/design/style/mica): el material del fondo de la ventana.
- [Navegación](https://learn.microsoft.com/windows/apps/design/basics/navigation-basics): barra lateral, lista y detalle.
- [Segoe Fluent Icons](https://learn.microsoft.com/windows/apps/design/style/segoe-fluent-icons-font): el equivalente a SF Symbols.
- [Diseño del ícono de la app](https://learn.microsoft.com/windows/apps/design/style/iconography/app-icon-design).
- [Accesibilidad](https://learn.microsoft.com/windows/apps/design/accessibility/accessibility).

Herramientas:

- [Windows Design Kit para Figma](https://learn.microsoft.com/windows/apps/design/downloads/): componentes, plantillas de layout y tokens de color, tipografía y espaciado.
- [WinUI 3 Gallery](https://github.com/microsoft/WinUI-Gallery), también en Microsoft Store: cada control funcionando, con su código y notas de diseño y accesibilidad. Es la referencia práctica más útil.
- Windows Community Toolkit Gallery: muestra `SettingsCard` y `SettingsExpander`, para los Ajustes.

Textos:

- [Writing style de Windows](https://learn.microsoft.com/windows/apps/design/style/writing-style) y la [Microsoft Writing Style Guide](https://learn.microsoft.com/style-guide/welcome/). Mismo criterio que en macOS: pocas palabras, tono directo, sin “nosotros”. En Windows se dice “PC”, “Explorador de archivos” y “Papelera de reciclaje”.

[Fluent 2](https://fluent2.microsoft.design/) está orientado a web, iOS, Android y apps como Teams u Office. Para una app nativa de Windows mandan Microsoft Learn y WinUI 3 Gallery.
